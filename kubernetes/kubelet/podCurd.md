&emsp;`Pod`的curd, pod的curd主要包含下面几个方法:
- `HandlePodAdditions`
- `HandlePodUpdates`
- `HandlePodRemoves`
- `HandlePodReconcile`
- `HandlePodUpdates`

```go 
func (kl *Kubelet) HandlePodAdditions(pods []*v1.Pod) {
	for _, pod := range pods {
		pod, mirrorPod, wasMirror := kl.podManager.GetPodAndMirrorPod(pod)
		if wasMirror {
			kl.podWorkers.UpdatePod(UpdatePodOptions{ Pod:        pod, MirrorPod:  mirrorPod, UpdateType: kubetypes.SyncPodUpdate, StartTime:  start, })
			continue
		}

		if !kl.podWorkers.IsPodTerminationRequested(pod.UID) {
            // admission checker
            // status setter .....
		}
		kl.podWorkers.UpdatePod(UpdatePodOptions{ Pod:        pod, MirrorPod:  mirrorPod, UpdateType: kubetypes.SyncPodCreate, StartTime:  start, })
	}
}

func (kl *Kubelet) HandlePodUpdates(pods []*v1.Pod) {
	for _, pod := range pods {
		pod, mirrorPod, wasMirror := kl.podManager.GetPodAndMirrorPod(pod)
		if wasMirror {
			if pod == nil { continue }
		}

		kl.podWorkers.UpdatePod(UpdatePodOptions{ Pod:        pod, MirrorPod:  mirrorPod, UpdateType: kubetypes.SyncPodUpdate, StartTime:  start, })
	}
}


func (kl *Kubelet) HandlePodRemoves(pods []*v1.Pod) {
	for _, pod := range pods {
		pod, mirrorPod, wasMirror := kl.podManager.GetPodAndMirrorPod(pod)
		if wasMirror {
            if pod  ==nil {continue}
			kl.podWorkers.UpdatePod(UpdatePodOptions{ Pod:        pod, MirrorPod:  mirrorPod, UpdateType: kubetypes.SyncPodUpdate, StartTime:  start, })
			continue
		}

		if err := kl.deletePod(pod); err != nil {
			klog.V(2).InfoS("Failed to delete pod", "pod", klog.KObj(pod), "err", err)
		}
	}
}


```

&emsp;从上面的逻辑看，所有的pod 的curd都在`podWorker'Update()`方法里面完成的

```go 

func newPodWorkers( podSyncer podSyncer, recorder record.EventRecorder, workQueue queue.WorkQueue, resyncInterval, backOffPeriod time.Duration, podCache kubecontainer.Cache,
) PodWorkers {
    // podSyncer -> kubelet
    // recorder -> kubeRecorder
    // workqueue -> klet.workQueue
    // podCache -> klet.podCache
	return &podWorkers{
		podSyncStatuses:                    map[types.UID]*podSyncStatus{}, 
		podUpdates:                         map[types.UID]chan struct{}{},
		startedStaticPodsByFullname:        map[string]types.UID{},
		waitingToStartStaticPodsByFullname: map[string][]types.UID{},
		podSyncer:                          podSyncer,
		recorder:                           recorder,
		workQueue:                          workQueue,
		resyncInterval:                     resyncInterval,
		backOffPeriod:                      backOffPeriod,
		podCache:                           podCache,
		clock:                              clock.RealClock{},
	}
}
```

