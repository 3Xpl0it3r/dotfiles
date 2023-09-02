
&emsp;`PodConfig`的逻辑
```go 
func makePodSourceConfig(kubeCfg *kuberconfiginternal.KubeletConfiguration, kubeDeps *Depencies, nodeName types.NodeName, nodeHasSynced func()bool)(*config.PodConfig, error){
    cfg := config.NewPodConfig(config.PodConfigNoticationIncremental, kubeDeps.Recorder, kubeDeps.PodStartupLatencyTracker)

    // 1. create channel named ChA in cfg.Channel methods
    // 2. run a goroutine G1, in this goroutine received object from channel ChA
    // 3. run a fswatch goroutine, monitor file system changed,
    // 4. run a goroutine G2, receive event from fswatch ,then send object to ChA
    config.NewSourceFile(kubecfg.StaticPodPath, nodeName, kubeCfg.FileCheckerFrequency.Duration, cfg.Channel(ctx, kubetypes.FileSource))

    config.NewSourceURL(kubecfg.StaticPodURL, mainfestURLHeader, nodeName, kubeCfg.HTTPCheckerFrequency.Duration, cfg.Channel(ctx, kubetypes.HTTPSource))

    // 1. create channel ChA in cfg.Channel
    // 2. run goroutine ,receive object from channel ChA
    // 3. run reflector, receive object from apiserver ,then send object to ChA
    config.NewSourceApiServer(kubeDeps.KubeClient, nodeName, nodeHasSynced, cfg.Channel(ctx, kubetypes.ApiserverSrouces))
}

func NewPodConfig(mode PodConfigNotificationMode, recorder record.EventRecorder, startupSLIObserver podStartupSLIObserver) *PodConfig {
	updates := make(chan kubetypes.PodUpdate, 50)
	storage := newPodStorage(updates, mode, recorder, startupSLIObserver)
	podConfig := &PodConfig{
		pods:    storage,
		mux:     config.NewMux(storage),
		updates: updates,
		sources: sets.String{},
	}
	return podConfig
}

func (c *PodConfig) Channel(ctx context.Context, source string) chan<- interface{} {
    // c.sources like a map
	c.sources.Insert(source) // c.sources[source] = struct{}{}

	newChannel := make(chan interface{})
    c.mux.sources[source] = newChannel

    go func(){
        for update := range newChannel{
            c.mux.merger.Merge(source ,update)
        }
    }
    return newChannel
}

// File Sources
func NewSourceFile(path string, nodeName types.NodeName, period time.Duration, updates chan<- interface{}) {
	// "github.com/sigma/go-inotify" requires a path without trailing "/"
	path = strings.TrimRight(path, string(os.PathSeparator))

	config := newSourceFile(path, nodeName, period, updates)
    config.run()
}
func newSourceFile(path string, nodeName types.NodeName, period time.Duration, updates chan<- interface{}) *sourceFile {
	send := func(objs []interface{}) {
		var pods []*v1.Pod
		for _, o := range objs {
			pods = append(pods, o.(*v1.Pod))
		}
		updates <- kubetypes.PodUpdate{Pods: pods, Op: kubetypes.SET, Source: kubetypes.FileSource}
	}
	store := cache.NewUndeltaStore(send, cache.MetaNamespaceKeyFunc)
	return &sourceFile{
		path:           path,
		nodeName:       nodeName,
		period:         period,
		store:          store,
		fileKeyMapping: map[string]string{},
		updates:        updates,
		watchEvents:    make(chan *watchEvent, eventBufferLen),
	}
}

func (s *sourceFile) run() {
	listTicker := time.NewTicker(s.period)

	go func() {
		// Read path immediately to speed up startup.
		if err := s.listConfig(); err != nil {
			klog.ErrorS(err, "Unable to read config path", "path", s.path)
		}
		for {
			select {
			case <-listTicker.C:
				if err := s.listConfig(); err != nil {
					klog.ErrorS(err, "Unable to read config path", "path", s.path)
				}
			case e := <-s.watchEvents:
				if err := s.consumeWatchEvent(e); err != nil {
					klog.ErrorS(err, "Unable to process watch event")
				}
			}
		}
	}()

    // start goruntime monitor file system changed
	s.startWatch()
}


// ApiServer logical
func NewSourceApiserver(c clientset.Interface, nodeName types.NodeName, nodeHasSynced func() bool, updates chan<- interface{}) {
	lw := cache.NewListWatchFromClient(c.CoreV1().RESTClient(), "pods", metav1.NamespaceAll, fields.OneTermEqualSelector("spec.nodeName", string(nodeName)))
	go func() {
		newSourceApiserverFromLW(lw, updates)
	}()
}

// newSourceApiserverFromLW holds creates a config source that watches and pulls from the apiserver.
func newSourceApiserverFromLW(lw cache.ListerWatcher, updates chan<- interface{}) {
	send := func(objs []interface{}) {
		var pods []*v1.Pod
		for _, o := range objs {
			pods = append(pods, o.(*v1.Pod))
		}
		updates <- kubetypes.PodUpdate{Pods: pods, Op: kubetypes.SET, Source: kubetypes.ApiserverSource}
	}
	r := cache.NewReflector(lw, &v1.Pod{}, cache.NewUndeltaStore(send, cache.MetaNamespaceKeyFunc), 0)
	go r.Run(wait.NeverStop)
}


```



