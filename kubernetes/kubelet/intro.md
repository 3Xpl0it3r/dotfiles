&emsp; some essential components
```go 
type Kubelet struct {
	podManager kubepod.Manager

	podWorkers PodWorkers

	evictionManager eviction.Manager

	probeManager prober.Manager

	secretManager secret.Manager

	configMapManager configmap.Manager

	volumeManager volumemanager.VolumeManager

	statusManager status.Manager


	// Optional, defaults to /logs/ from /var/log
	logServer http.Handler
	// Optional, defaults to simple Docker implementation
	runner kubecontainer.CommandRunner

	// cAdvisor used for container information.
	cadvisor cadvisor.Interface

	// Set to true to have the node register itself with the apiserver.
	registerNode bool
	// List of taints to add to a node object when the kubelet registers itself.
	registerWithTaints []v1.Taint
	// Set to true to have the node register itself as schedulable.
	registerSchedulable bool
	// for internal book keeping; access only from within registerWithApiserver
	registrationCompleted bool

	// dnsConfigurer is used for setting up DNS resolver configuration when launching pods.
	dnsConfigurer *dns.Configurer


	// Last timestamp when runtime responded on ping.
	// Mutex is used to protect this value.
	runtimeState *runtimeState

	// Volume plugins.
	volumePluginMgr *volume.VolumePluginMgr

	// Manages container health check results.
	livenessManager  proberesults.Manager
	readinessManager proberesults.Manager
	startupManager   proberesults.Manager

	// How long to keep idle streaming command execution/port forwarding
	// connections open before terminating them
	streamingConnectionIdleTimeout time.Duration


	containerGC kubecontainer.GC

	// Manager for image garbage collection.
	imageManager images.ImageGCManager

	// Manager for container logs.
	containerLogManager logs.ContainerLogManager


	// Handles certificate rotations.
	serverCertificateManager certificate.Manager


	// Container runtime.
	containerRuntime kubecontainer.Runtime

	// Streaming runtime handles container streaming.
	streamingRuntime kubecontainer.StreamingRuntime

	// Container runtime service (needed by container runtime Start()).
	runtimeService internalapi.RuntimeService

	// reasonCache caches the failure reason of the last creation of all containers, which is
	// used for generating ContainerStatus.
	reasonCache *ReasonCache

	// nodeLeaseController claims and renews the node lease for this Kubelet
	nodeLeaseController lease.Controller

	pleg pleg.PodLifecycleEventGenerator
	eventedPleg pleg.PodLifecycleEventGenerator

	// Store kubecontainer.PodStatus for all pods.
	podCache kubecontainer.Cache

	// os is a facade for various syscalls that need to be mocked during testing.
	os kubecontainer.OSInterface

	// Watcher of out of memory events.
	oomWatcher oomwatcher.Watcher

	// Monitor resource usage
	resourceAnalyzer serverstats.ResourceAnalyzer

	// Manager of non-Runtime containers.
	containerManager cm.ContainerManager

	// the list of handlers to call during pod sync loop.
	lifecycle.PodSyncLoopHandlers

	// the list of handlers to call during pod sync.
	lifecycle.PodSyncHandlers

	pluginManager pluginmanager.PluginManager

	// Handles RuntimeClass objects for the Kubelet.
	runtimeClassManager *runtimeclass.Manager

	// Handles node shutdown events for the Node.
	shutdownManager nodeshutdown.Manager

	// Manage user namespaces
	usernsManager *userns.UsernsManager

	// Mutex to serialize new pod admission and existing pod resizing
	podResizeMutex sync.Mutex

}
```


&emsp; 下面是启动`kubelet`的代码
```go
func (kl *Kubelet) Run (updates <- chan kubetypes.PodUpdate) {
    // 0 initializeModules 
    { // kl.initializeModules(0)
        // setup some direcoters
        kl.imageManager.Start()

        kl.serverCertificateManager.Start(0)

        kl.oomWatcher.Start()

        kl.resourceAnalyzer.Start()
    }

    // 1 
    go kl.volumeManager.Run(kl.sourcesReady, wait.NeverStop)

    // 2 (none standonly mode)
    go wait.JitterUntil(kl.syncNodeStatus, kl.nodeStatusUpdateFrequency, 0.04, true, wait.NeverStop)
    go kl.fastStatusUpdateOnce()
    go kl.nodeLeaseController.Run(context.Background())

    // 3 
    go wait.Until(kl.updateRuntimeUp, 5 * time.Second, wait.NeverStop)

    // 4
    kl.statusManager.Start()

    // 5
    kl.runtimeClassManager.Start(wait.NeverStop)

    // 6, Start pod lifecycle event generator
    kl.pleg.Start()

    // 7 start infinite loop 
    kl.syncLoop(ctx, updates, kl)
}
```



&emsp; infinite loop's logic

```go 
func (kl *Kubelet) syncLoopIteration(ctx context.Context, configCh <-chan kubetypes.PodUpdate, handler SyncHandler,
	syncCh <-chan time.Time, housekeepingCh <-chan time.Time, plegCh <-chan *pleg.PodLifecycleEvent) bool {

	select {
	case u, open := <-configCh:
		switch u.Op {
		case kubetypes.ADD:
			handler.HandlePodAdditions(u.Pods)
		case kubetypes.UPDATE:
			handler.HandlePodUpdates(u.Pods)
		case kubetypes.REMOVE:
			handler.HandlePodRemoves(u.Pods)
		case kubetypes.RECONCILE:
			handler.HandlePodReconcile(u.Pods)
		case kubetypes.DELETE:
			handler.HandlePodUpdates(u.Pods)
		case kubetypes.SET:
			klog.ErrorS(nil, "Kubelet does not support snapshot update")
		default:
			klog.ErrorS(nil, "Invalid operation type received", "operation", u.Op)
		}

		kl.sourcesReady.AddSource(u.Source)

	case e := <-plegCh:
		if pod, ok := kl.podManager.GetPodByUID(e.ID); ok {
			klog.V(2).InfoS("SyncLoop (PLEG): event for pod", "pod", klog.KObj(pod), "event", e)
		    handler.HandlePodSyncs([]*v1.Pod{pod})
		} else {
			klog.V(4).InfoS("SyncLoop (PLEG): pod does not exist, ignore irrelevant event", "event", e)
		}

		if e.Type == pleg.ContainerDied {
			if containerID, ok := e.Data.(string); ok {
				kl.cleanUpContainersInPod(e.ID, containerID)
			}
		}
	case <-syncCh:
		// Sync pods waiting for sync
		podsToSync := kl.getPodsToSync()
		if len(podsToSync) == 0 {
			break
		}
		klog.V(4).InfoS("SyncLoop (SYNC) pods", "total", len(podsToSync), "pods", klog.KObjSlice(podsToSync))
		handler.HandlePodSyncs(podsToSync)
	case update := <-kl.livenessManager.Updates():
		if update.Result == proberesults.Failure {
			handleProbeSync(kl, update, handler, "liveness", "unhealthy")
		}
	case update := <-kl.readinessManager.Updates():
		ready := update.Result == proberesults.Success
		kl.statusManager.SetContainerReadiness(update.PodUID, update.ContainerID, ready)

		status := ""
		if ready {
			status = "ready"
		}
		handleProbeSync(kl, update, handler, "readiness", status)
	case update := <-kl.startupManager.Updates():
		started := update.Result == proberesults.Success
		kl.statusManager.SetContainerStartup(update.PodUID, update.ContainerID, started)

		status := "unhealthy"
		if started {
			status = "started"
		}
		handleProbeSync(kl, update, handler, "startup", status)
	case <-housekeepingCh:
		if !kl.sourcesReady.AllReady() {
			// If the sources aren't ready or volume manager has not yet synced the states,
			// skip housekeeping, as we may accidentally delete pods from unready sources.
			klog.V(4).InfoS("SyncLoop (housekeeping, skipped): sources aren't ready yet")
		} else {
			start := time.Now()
			klog.V(4).InfoS("SyncLoop (housekeeping)")
			if err := handler.HandlePodCleanups(ctx); err != nil {
				klog.ErrorS(err, "Failed cleaning pods")
			}
			duration := time.Since(start)
			if duration > housekeepingWarningDuration {
				klog.ErrorS(fmt.Errorf("housekeeping took too long"), "Housekeeping took longer than expected", "expected", housekeepingWarningDuration, "actual", duration.Round(time.Millisecond))
			}
			klog.V(4).InfoS("SyncLoop (housekeeping) end", "duration", duration.Round(time.Millisecond))
		}
	}
	return true

}
```
