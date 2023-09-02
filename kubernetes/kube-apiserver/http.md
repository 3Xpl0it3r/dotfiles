&emsp;抛开kubernetes ,kube-apiserver 它是一个提供某些功能的http server, 先从http server角度来看需要了解 route和handler 

&emsp;和http server相关的一些参数
```go
// 主要关注两个参数,SecureServing `Secure serving flags`
// 默认参数
type SecureServingOptions struct {
	BindAddress net.IP // 监听的地址 --bind-address 默认0.0.0.0
	BindPort int  // 监听的端口. 默认6443
	BindNetwork string //监听协议 默认tcp (tcp, tcp4, tcp6)
	Required bool // true 意味着bindport不能为0,
	ExternalAddress net.IP
	Listener net.Listener
	ServerCert GeneratableKeyCert // 涉及2个参数--cert-dir(如果不制定，他会默认创建一个在cert-dir目录下), --tls-private-key-file, 以及--tls-cert-file
	SNICertKeys []cliflag.NamedCertKey
    // .... 下面参数不重要
}

// kube-apiserver 本身的options 
type ServerRunOptions struct {
	AdvertiseAddress net.IP

	CorsAllowedOriginList       []string
	HSTSDirectives              []string
	ExternalHost                string
    // .....
}

// 其他的options
ServiceAccountSigningKeyFile     string
ServiceAccountIssuer             serviceaccount.TokenGenerator
ServiceAccountTokenMaxExpiration time.Duration

```
#### ArgsParse 填充完用户自定义的值之后，来设默认值

```go 
// step 1
// s := options.NewServerRunOptions() //创建options
// step2
// completedOptions, err := s.Complete() // 填充默认值
func (opts *ServerRunOptions) Complete() (CompletedOptions, error) {

    // 设置apiserverIp, 默认10.96.0.0 kubeadm会传给他
	apiServerServiceIP, primaryServiceIPRange, secondaryServiceIPRange, err := getServiceIPAndRanges(opts.ServiceClusterIPRanges)

    // 执行options.Complkete
	controlplane, err := opts.Options.Complete([]string{"kubernetes.default.svc", "kubernetes.default", "kubernetes"}, []net.IP{apiServerServiceIP})

	completed := completedOptions{
		CompletedOptions: controlplane,
		CloudProvider:    opts.CloudProvider,
		Extra: opts.Extra,
	}

	completed.PrimaryServiceClusterIPRange = primaryServiceIPRange
	completed.SecondaryServiceClusterIPRange = secondaryServiceIPRange
	completed.APIServerServiceIP = apiServerServiceIP
    // ectd相关一些配置

	return CompletedOptions{
		completedOptions: &completed,
	}, nil
}
// Options.Complete相关设置
func (o *Options) Complete(alternateDNS []string, alternateIPs []net.IP) (CompletedOptions, error) {
	completed := completedOptions{ Options: *o, }

	// set defaults  AdvertiseAddress = hostIP (根据secureService.BindAddress 来计算 externalIP) 
	if err := completed.GenericServerRunOptions.DefaultAdvertiseAddress(completed.SecureServing.SecureServingOptions); err != nil { return CompletedOptions{}, err }

    // 如果--tls-private-key-file提供的话, 则使用自定义,如果没提供则使用在 /cert/下面创建一个
	completed.SecureServing.MaybeDefaultWithSelfSignedCerts(completed.GenericServerRunOptions.AdvertiseAddress.String(), alternateDNS, alternateIPs)


	if completed.ServiceAccountSigningKeyFile == "" {
		completed.Authentication.ServiceAccounts.KeyFiles = []string{completed.SecureServing.ServerCert.CertKey.KeyFile}
        // 如果--service-account-signing-key-file值未提供, 则使用service --tls-private-key-file作为key
	}

    // 如果service-account-signing-key-file 提供，并且serviceAccount.issuer 也提供了的话
	if completed.ServiceAccountSigningKeyFile != "" && len(completed.Authentication.ServiceAccounts.Issuers) != 0 && completed.Authentication.ServiceAccounts.Issuers[0] != "" {
		sk, err := keyutil.PrivateKeyFromFile(completed.ServiceAccountSigningKeyFile) // 获取singing-key-file的key
        // 生成JWTTokenGenerator  认证
		completed.ServiceAccountIssuer, err = serviceaccount.JWTTokenGenerator(completed.Authentication.ServiceAccounts.Issuers[0], sk)
	}

	return CompletedOptions{ completedOptions: &completed, }, nil
}

```

#### Option阶段已经完成, 根据Option生成配置文件
```go 
// 	config, err := NewConfig(opts)
func NewConfig(opts options.CompletedOptions) (*Config, error) {
	c := &Config{ Options: opts, }
    // 生成kubeApiServer配置文件
	controlPlane, serviceResolver, pluginInitializer, err := CreateKubeAPIServerConfig(opts)
	c.ControlPlane = controlPlane

    // 生成apiextension server配置文件
	apiExtensions, err := apiserver.CreateAPIExtensionsConfig(*controlPlane.GenericConfig, controlPlane.ExtraConfig.VersionedInformers, pluginInitializer, opts.CompletedOptions, opts.MasterCount,
		serviceResolver, webhook.NewDefaultAuthenticationInfoResolverWrapper(controlPlane.ExtraConfig.ProxyTransport, controlPlane.GenericConfig.EgressSelector, controlPlane.GenericConfig.LoopbackClientConfig, controlPlane.GenericConfig.TracerProvider))
	c.ApiExtensions = apiExtensions

    // 生成aggregator server配置文件
	aggregator, err := createAggregatorConfig(*controlPlane.GenericConfig, opts.CompletedOptions, controlPlane.ExtraConfig.VersionedInformers, serviceResolver, controlPlane.ExtraConfig.ProxyTransport, controlPlane.ExtraConfig.PeerProxy, pluginInitializer)
	if err != nil {
		return nil, err
	}
	c.Aggregator = aggregator
	return c, nil
}
```


##### KubeApiServer配置文件
```go 
// GenericConfig 主要功能有authentication, authorization ,aduit, admission 
// 生成配置文件的逻辑如下
// BuildGenericKubeAPiserverConfig (-> call genericApiServerConfig) -> init some config
func CreateKubeAPIServerConfig(opts options.CompletedOptions) ( *controlplane.Config, aggregatorapiserver.ServiceResolver, []admission.PluginInitializer, error,) {
	proxyTransport := CreateProxyTransport()

	genericConfig, versionedInformers, storageFactory, err := controlplaneapiserver.BuildGenericConfig(
		opts.CompletedOptions,
		[]*runtime.Scheme{legacyscheme.Scheme, extensionsapiserver.Scheme, aggregatorscheme.Scheme},
		generatedopenapi.GetOpenAPIDefinitions,
	)

	config := &controlplane.Config{
		GenericConfig: genericConfig,
		ExtraConfig: controlplane.ExtraConfig{
			APIResourceConfigSource: storageFactory.APIResourceConfigSource,
			StorageFactory:          storageFactory,
			KubeletClientConfig:     opts.KubeletConfig,
			ProxyTransport:          proxyTransport,
			ServiceAccountIssuer:        opts.ServiceAccountIssuer,
			ServiceAccountMaxExpiration: opts.ServiceAccountTokenMaxExpiration,
			ExtendExpiration:            opts.Authentication.ServiceAccounts.ExtendExpiration,
			VersionedInformers: versionedInformers, },
	}


    // 获取client ca provider
	clientCAProvider, err := opts.Authentication.ClientCert.GetClientCAContentProvider()
	config.ExtraConfig.ClusterAuthenticationInfo.ClientCA = clientCAProvider

    // 获取--requestheader-client-ca-file 
	requestHeaderConfig, err := opts.Authentication.RequestHeader.ToAuthenticationRequestHeaderConfig()
	if requestHeaderConfig != nil {
		// config.ExtraConfig.ClusterAuthenticationInfo相关设置
	}

	// 配置admission
	admissionConfig := &kubeapiserveradmission.Config{
		ExternalInformers:    versionedInformers,
		LoopbackClientConfig: genericConfig.LoopbackClientConfig,
		CloudConfigFile:      opts.CloudProvider.CloudConfigFile,
	}
    config.AdmissionController = []Handler{somePlugins}

	var pubKeys []interface{}
	for _, f := range opts.Authentication.ServiceAccounts.KeyFiles {
		keys, err := keyutil.PublicKeysFromFile(f)
		if err != nil {
			return nil, nil, nil, fmt.Errorf("failed to parse key file %q: %v", f, err)
		}
		pubKeys = append(pubKeys, keys...)
	}
	config.ExtraConfig.ServiceAccountIssuerURL = opts.Authentication.ServiceAccounts.Issuers[0]
	config.ExtraConfig.ServiceAccountJWKSURI = opts.Authentication.ServiceAccounts.JWKSURI
	config.ExtraConfig.ServiceAccountPublicKeys = pubKeys

	return config, serviceResolver, pluginInitializers, nil
}


// buildGenericConfig
func BuildGenericConfig( s controlplaneapiserver.CompletedOptions, schemes []*runtime.Scheme, getOpenAPIDefinitions func(ref openapicommon.ReferenceCallback) map[string]openapicommon.OpenAPIDefinition,) ( genericConfig *genericapiserver.Config, versionedInformers clientgoinformers.SharedInformerFactory, storageFactory *serverstorage.DefaultStorageFactory, lastErr error,) {
	genericConfig = genericapiserver.NewConfig(legacyscheme.Codecs) //  genericConfig =&Config{Serializer, DefaultBuildHandler}
	genericConfig.MergedResourceConfig = controlplane.DefaultAPIResourceConfigSource() // APiResourceConfig{version {v1: true, v2: false}, resource: {rs1: true, rs2: false}}

    // (*secureServingInfo).SNICerts = (*secureServingInfo).SNICerts[1:] lookback cert /lookbackClientConfig
	s.SecureServing.ApplyTo(&genericConfig.SecureServing, &genericConfig.LoopbackClientConfig); lastErr != nil {
    // storage相关
    // 内部通信走protobuf， 并且不开启压缩功能
	// Authentication.ApplyTo requires already applied OpenAPIConfig and EgressSelector if present
    s.Authenticator = Authenticator

    s.Authorizator = Authorizator

    s.Auditor = Auditor

}
```
##### APiExtension配置文件
```go 
// apiextension的配置文件基本上差不多
func CreateAPIExtensionsConfig( kubeAPIServerConfig server.Config, kubeInformers informers.SharedInformerFactory, pluginInitializers []admission.PluginInitializer, commandOptions controlplaneapiserver.CompletedOptions, masterCount int, serviceResolver webhook.ServiceResolver, authResolverWrapper webhook.AuthenticationInfoResolverWrapper,) (*apiextensionsapiserver.Config, error) {
	genericConfig := kubeAPIServerConfig
	genericConfig.PostStartHooks = map[string]server.PostStartHookConfigEntry{}
	genericConfig.RESTOptionsGetter = nil
	etcdOptions.StorageConfig.Codec = apiextensionsapiserver.Codecs.LegacyCodec(v1beta1.SchemeGroupVersion, v1.SchemeGroupVersion)
	etcdOptions.StorageConfig.EncodeVersioner = runtime.NewMultiGroupVersioner(v1beta1.SchemeGroupVersion, schema.GroupKind{Group: v1beta1.GroupName})

	// override MergedResourceConfig with apiextensions defaults and registry
    // genericConfig.APIMergerResource = {apiextension/v1 apiextension/v1beta1}
	commandOptions.APIEnablement.ApplyTo( &genericConfig, apiextensionsapiserver.DefaultAPIResourceConfigSource(), apiextensionsapiserver.Scheme)

	apiextensionsConfig := &apiextensionsapiserver.Config{
		GenericConfig: &server.RecommendedConfig{
			Config:                genericConfig,
			SharedInformerFactory: kubeInformers,
		},
		ExtraConfig: apiextensionsapiserver.ExtraConfig{
			CRDRESTOptionsGetter: apiextensionsoptions.NewCRDRESTOptionsGetter(etcdOptions, genericConfig.ResourceTransformers, genericConfig.StorageObjectCountTracker),
			MasterCount:          masterCount,
			AuthResolverWrapper:  authResolverWrapper,
			ServiceResolver:      serviceResolver,
		},
	}

	// we need to clear the poststarthooks so we don't add them multiple times to all the servers (that fails)
	apiextensionsConfig.GenericConfig.PostStartHooks = map[string]server.PostStartHookConfigEntry{}

	return apiextensionsConfig, nil
}
```
##### Aggregator配置文件
```go
// aggregator  
func createAggregatorConfig( kubeAPIServerConfig genericapiserver.Config, commandOptions controlplaneapiserver.CompletedOptions, externalInformers kubeexternalinformers.SharedInformerFactory, serviceResolver aggregatorapiserver.ServiceResolver, proxyTransport *http.Transport, peerProxy utilpeerproxy.Interface, pluginInitializers []admission.PluginInitializer,) (*aggregatorapiserver.Config, error) {
	// make a shallow copy to let us twiddle a few things
	// most of the config actually remains the same.  We only need to mess with a couple items related to the particulars of the aggregator
	genericConfig := kubeAPIServerConfig
	genericConfig.PostStartHooks = map[string]genericapiserver.PostStartHookConfigEntry{}
	genericConfig.RESTOptionsGetter = nil
	// prevent generic API server from installing the OpenAPI handler. Aggregator server
	// has its own customized OpenAPI handler.
	genericConfig.SkipOpenAPIInstallation = true

	if utilfeature.DefaultFeatureGate.Enabled(genericfeatures.StorageVersionAPI) &&
		utilfeature.DefaultFeatureGate.Enabled(genericfeatures.APIServerIdentity) {
		// Add StorageVersionPrecondition handler to aggregator-apiserver.
		// The handler will block write requests to built-in resources until the
		// target resources' storage versions are up-to-date.
		genericConfig.BuildHandlerChainFunc = genericapiserver.BuildHandlerChainWithStorageVersionPrecondition
	}

	if peerProxy != nil {
		originalHandlerChainBuilder := genericConfig.BuildHandlerChainFunc
		genericConfig.BuildHandlerChainFunc = func(apiHandler http.Handler, c *genericapiserver.Config) http.Handler {
			// Add peer proxy handler to aggregator-apiserver.
			// wrap the peer proxy handler first.
			apiHandler = peerProxy.WrapHandler(apiHandler)
			return originalHandlerChainBuilder(apiHandler, c)
		}
	}

	// copy the etcd options so we don't mutate originals.
	// we assume that the etcd options have been completed already.  avoid messing with anything outside
	// of changes to StorageConfig as that may lead to unexpected behavior when the options are applied.
	etcdOptions := *commandOptions.Etcd
	etcdOptions.StorageConfig.Paging = true
	etcdOptions.StorageConfig.Codec = aggregatorscheme.Codecs.LegacyCodec(v1.SchemeGroupVersion, v1beta1.SchemeGroupVersion)
	etcdOptions.StorageConfig.EncodeVersioner = runtime.NewMultiGroupVersioner(v1.SchemeGroupVersion, schema.GroupKind{Group: v1beta1.GroupName})
	etcdOptions.SkipHealthEndpoints = true // avoid double wiring of health checks
	if err := etcdOptions.ApplyTo(&genericConfig); err != nil {
		return nil, err
	}

	// override MergedResourceConfig with aggregator defaults and registry
    // genericCOnfig.MergedResourceConfig = {apiregistry/v1 apiregistery/v1beta1}
	if err := commandOptions.APIEnablement.ApplyTo(
		&genericConfig,
		aggregatorapiserver.DefaultAPIResourceConfigSource(),
		aggregatorscheme.Scheme); err != nil {
		return nil, err
	}

	aggregatorConfig := &aggregatorapiserver.Config{
		GenericConfig: &genericapiserver.RecommendedConfig{
			Config:                genericConfig,
			SharedInformerFactory: externalInformers,
		},
		ExtraConfig: aggregatorapiserver.ExtraConfig{
			ProxyClientCertFile:       commandOptions.ProxyClientCertFile,
			ProxyClientKeyFile:        commandOptions.ProxyClientKeyFile,
			PeerCAFile:                commandOptions.PeerCAFile,
			PeerAdvertiseAddress:      commandOptions.PeerAdvertiseAddress,
			ServiceResolver:           serviceResolver,
			ProxyTransport:            proxyTransport,
			RejectForwardingRedirects: commandOptions.AggregatorRejectForwardingRedirects,
		},
	}

	// we need to clear the poststarthooks so we don't add them multiple times to all the servers (that fails)
	aggregatorConfig.GenericConfig.PostStartHooks = map[string]genericapiserver.PostStartHookConfigEntry{}

	return aggregatorConfig, nil
}
```



#### 配置文件默认值填充(如果option里面没有，那么这个地方会填充下默认字段)
```go 
// 通用的配置
func (c *Config) Complete(informers informers.SharedInformerFactory) CompletedConfig {

	// if there is no port, and we listen on one securely, use that one
	AuthorizeClientBearerToken(c.LoopbackClientConfig, &c.Authentication, &c.Authorization)

	if c.RequestInfoResolver == nil {
		c.RequestInfoResolver = NewRequestInfoResolver(c)
	}

	return CompletedConfig{&completedConfig{c, informers}}
}

// Apiexntesion 字段
func (cfg *Config) Complete() CompletedConfig {
	c := completedConfig{ cfg.GenericConfig.Complete(), &cfg.ExtraConfig, }
	c.GenericConfig.EnableDiscovery = false

	return CompletedConfig{&c}
}

// kubeapiserver 
func (c *Config) Complete() CompletedConfig {
	cfg := completedConfig{ c.GenericConfig.Complete(c.ExtraConfig.VersionedInformers), &c.ExtraConfig, }

	serviceIPRange, apiServerServiceIP, err := options.ServiceIPRange(cfg.ExtraConfig.ServiceIPRange)

	discoveryAddresses := discovery.DefaultAddresses{DefaultAddress: cfg.GenericConfig.ExternalAddress}
	discoveryAddresses.CIDRRules = append(discoveryAddresses.CIDRRules,
		discovery.CIDRRule{IPRange: cfg.ExtraConfig.ServiceIPRange, Address: net.JoinHostPort(cfg.ExtraConfig.APIServerServiceIP.String(), strconv.Itoa(cfg.ExtraConfig.APIServerServicePort))})
	cfg.GenericConfig.DiscoveryAddresses = discoveryAddresses

	if cfg.ExtraConfig.ServiceNodePortRange.Size == 0 {
		// TODO: Currently no way to specify an empty range (do we need to allow this?)
		// We should probably allow this for clouds that don't require NodePort to do load-balancing (GCE)
		// but then that breaks the strict nestedness of ServiceType.
		// Review post-v1
		cfg.ExtraConfig.ServiceNodePortRange = kubeoptions.DefaultServiceNodePortRange
		klog.Infof("Node port range unspecified. Defaulting to %v.", cfg.ExtraConfig.ServiceNodePortRange)
	}

	if cfg.ExtraConfig.EndpointReconcilerConfig.Interval == 0 {
		cfg.ExtraConfig.EndpointReconcilerConfig.Interval = DefaultEndpointReconcilerInterval
	}

	if cfg.ExtraConfig.MasterEndpointReconcileTTL == 0 {
		cfg.ExtraConfig.MasterEndpointReconcileTTL = DefaultEndpointReconcilerTTL
	}

	if cfg.ExtraConfig.EndpointReconcilerConfig.Reconciler == nil {
		cfg.ExtraConfig.EndpointReconcilerConfig.Reconciler = c.createEndpointReconciler()
	}

	if cfg.ExtraConfig.RepairServicesInterval == 0 {
		cfg.ExtraConfig.RepairServicesInterval = repairLoopInterval
	}

	return CompletedConfig{&cfg}
}


// aggregator 字段
func (cfg *Config) Complete() CompletedConfig {
	c := completedConfig{ cfg.GenericConfig.Complete(), &cfg.ExtraConfig, }

	// the kube aggregator wires its own discovery mechanism
	// TODO eventually collapse this by extracting all of the discovery out
	c.GenericConfig.EnableDiscovery = false
	version := version.Get()
	c.GenericConfig.Version = &version

	return CompletedConfig{&c}
}

```

&emsp;根据配置文件实例化APIserver
```go 
func CreateServerChain(config CompletedConfig) (*aggregatorapiserver.APIAggregator, error) {
    // MuxAndDiscoveryInstallationNotComplete 所有经过gorestful处理的都会带上这样一个字段
	notFoundHandler := notfoundhandler.New(config.ControlPlane.GenericConfig.Serializer, genericapifilters.NoMuxAndDiscoveryIncompleteKey) 
    // 创建APiExtension APiServer
	apiExtensionsServer, err := config.ApiExtensions.New(genericapiserver.NewEmptyDelegateWithCustomHandler(notFoundHandler))
	crdAPIEnabled := config.ApiExtensions.GenericConfig.MergedResourceConfig.ResourceEnabled(apiextensionsv1.SchemeGroupVersion.WithResource("customresourcedefinitions"))

    // 创建kubeAPIserver 
	kubeAPIServer, err := config.ControlPlane.New(apiExtensionsServer.GenericAPIServer)
	if err != nil {
		return nil, err
	}

    // 创建aggregator 
	aggregatorServer, err := createAggregatorServer(config.Aggregator, kubeAPIServer.GenericAPIServer, apiExtensionsServer.Informers, crdAPIEnabled)
	if err != nil {
		// we don't need special handling for innerStopCh because the aggregator server doesn't create any go routines
		return nil, err
	}

	return aggregatorServer, nil
}
```

##### common generic apiserver 
```go 
// genericServer, err := c.GenericConfig.New("apiextensions-apiserver", delegationTarget)
func (c completedConfig) New(name string, delegationTarget DelegationTarget) (*GenericAPIServer, error) {
	handlerChainBuilder := func(handler http.Handler) http.Handler {
		return c.BuildHandlerChainFunc(handler, c.Config)
	}
	apiServerHandler := NewAPIServerHandler(name, c.Serializer, handlerChainBuilder, delegationTarget.UnprotectedHandler()) // 空的mux
	s := &GenericAPIServer{
		legacyAPIGroupPrefixes:         c.LegacyAPIGroupPrefixes,
		admissionControl:               c.AdmissionControl,
		Serializer:                     c.Serializer,
		AuditBackend:                   c.AuditBackend,
		Authorizer:                     c.Authorization.Authorizer,
		delegationTarget:               delegationTarget,
		Handler:                        apiServerHandler,
		listedPathProvider: apiServerHandler,
		SecureServingInfo:                   c.SecureServing,
		ExternalAddress:                     c.ExternalAddress,

		DiscoveryGroupManager: discovery.NewRootAPIsHandler(c.DiscoveryAddresses, c.Serializer),
		StorageVersionManager: c.StorageVersionManager,
	}

	s.listedPathProvider = routes.ListedPathProviders{s.listedPathProvider, delegationTarget}

	installAPI(s, c.Config) // unhealth apis version proffile health

	return s, nil
}


```

##### apiExtension apiserver
```go 
// k8s.io/apiextesions-server/pkg/apiserver/apiserver.go
// New returns a new instance of CustomResourceDefinitions from the given config.
func (c completedConfig) New(delegationTarget genericapiserver.DelegationTarget) (*CustomResourceDefinitions, error) {
	genericServer, err := c.GenericConfig.New("apiextensions-apiserver", delegationTarget) // 一个空的mux 

	s := &CustomResourceDefinitions{ GenericAPIServer: genericServer, }

	apiResourceConfig := c.GenericConfig.MergedResourceConfig // 
	apiGroupInfo := genericapiserver.NewDefaultAPIGroupInfo(apiextensions.GroupName, Scheme, metav1.ParameterCodec, Codecs)
	storage := map[string]rest.Storage{}
	// customresourcedefinitions
	if resource := "customresourcedefinitions"; apiResourceConfig.ResourceEnabled(v1.SchemeGroupVersion.WithResource(resource)) {
		customResourceDefinitionStorage, err := customresourcedefinition.NewREST(Scheme, c.GenericConfig.RESTOptionsGetter)
		if err != nil {
			return nil, err
		}
		storage[resource] = customResourceDefinitionStorage
		storage[resource+"/status"] = customresourcedefinition.NewStatusREST(Scheme, customResourceDefinitionStorage)
	}
	if len(storage) > 0 {
		apiGroupInfo.VersionedResourcesStorageMap[v1.SchemeGroupVersion.Version] = storage
	}

    // 注册路由
	if err := s.GenericAPIServer.InstallAPIGroup(&apiGroupInfo); err != nil {
		return nil, err
	}

	crdClient, err := clientset.NewForConfig(s.GenericAPIServer.LoopbackClientConfig)
	if err != nil {
		// it's really bad that this is leaking here, but until we can fix the test (which I'm pretty sure isn't even testing what it wants to test),
		// we need to be able to move forward
		return nil, fmt.Errorf("failed to create clientset: %v", err)
	}
	s.Informers = externalinformers.NewSharedInformerFactory(crdClient, 5*time.Minute)

	delegateHandler := delegationTarget.UnprotectedHandler()
	if delegateHandler == nil {
		delegateHandler = http.NotFoundHandler()
	}

	versionDiscoveryHandler := &versionDiscoveryHandler{
		discovery: map[schema.GroupVersion]*discovery.APIVersionHandler{},
		delegate:  delegateHandler,
	}
	groupDiscoveryHandler := &groupDiscoveryHandler{
		discovery: map[string]*discovery.APIGroupHandler{},
		delegate:  delegateHandler,
	}
	establishingController := establish.NewEstablishingController(s.Informers.Apiextensions().V1().CustomResourceDefinitions(), crdClient.ApiextensionsV1())
	crdHandler, err := NewCustomResourceDefinitionHandler(
		versionDiscoveryHandler,
		groupDiscoveryHandler,
		s.Informers.Apiextensions().V1().CustomResourceDefinitions(),
		delegateHandler,
		c.ExtraConfig.CRDRESTOptionsGetter,
		c.GenericConfig.AdmissionControl,
		establishingController,
		c.ExtraConfig.ServiceResolver,
		c.ExtraConfig.AuthResolverWrapper,
		c.ExtraConfig.MasterCount,
		s.GenericAPIServer.Authorizer,
		c.GenericConfig.RequestTimeout,
		time.Duration(c.GenericConfig.MinRequestTimeout)*time.Second,
		apiGroupInfo.StaticOpenAPISpec,
		c.GenericConfig.MaxRequestBodyBytes,
	)
	if err != nil {
		return nil, err
	}
	s.GenericAPIServer.Handler.NonGoRestfulMux.Handle("/apis", crdHandler)
	s.GenericAPIServer.Handler.NonGoRestfulMux.HandlePrefix("/apis/", crdHandler)
	s.GenericAPIServer.RegisterDestroyFunc(crdHandler.destroy)

	aggregatedDiscoveryManager := genericServer.AggregatedDiscoveryGroupManager
	if aggregatedDiscoveryManager != nil {
		aggregatedDiscoveryManager = aggregatedDiscoveryManager.WithSource(aggregated.CRDSource)
	}
	discoveryController := NewDiscoveryController(s.Informers.Apiextensions().V1().CustomResourceDefinitions(), versionDiscoveryHandler, groupDiscoveryHandler, aggregatedDiscoveryManager)
	namingController := status.NewNamingConditionController(s.Informers.Apiextensions().V1().CustomResourceDefinitions(), crdClient.ApiextensionsV1())
	nonStructuralSchemaController := nonstructuralschema.NewConditionController(s.Informers.Apiextensions().V1().CustomResourceDefinitions(), crdClient.ApiextensionsV1())
	apiApprovalController := apiapproval.NewKubernetesAPIApprovalPolicyConformantConditionController(s.Informers.Apiextensions().V1().CustomResourceDefinitions(), crdClient.ApiextensionsV1())
	finalizingController := finalizer.NewCRDFinalizer(
		s.Informers.Apiextensions().V1().CustomResourceDefinitions(),
		crdClient.ApiextensionsV1(),
		crdHandler,
	)

	s.GenericAPIServer.AddPostStartHookOrDie("start-apiextensions-informers", func(context genericapiserver.PostStartHookContext) error {
		s.Informers.Start(context.StopCh)
		return nil
	})
	s.GenericAPIServer.AddPostStartHookOrDie("start-apiextensions-controllers", func(context genericapiserver.PostStartHookContext) error {
		// OpenAPIVersionedService and StaticOpenAPISpec are populated in generic apiserver PrepareRun().
		// Together they serve the /openapi/v2 endpoint on a generic apiserver. A generic apiserver may
		// choose to not enable OpenAPI by having null openAPIConfig, and thus OpenAPIVersionedService
		// and StaticOpenAPISpec are both null. In that case we don't run the CRD OpenAPI controller.
		if s.GenericAPIServer.StaticOpenAPISpec != nil {
			if s.GenericAPIServer.OpenAPIVersionedService != nil {
				openapiController := openapicontroller.NewController(s.Informers.Apiextensions().V1().CustomResourceDefinitions())
				go openapiController.Run(s.GenericAPIServer.StaticOpenAPISpec, s.GenericAPIServer.OpenAPIVersionedService, context.StopCh)
			}

			if s.GenericAPIServer.OpenAPIV3VersionedService != nil && utilfeature.DefaultFeatureGate.Enabled(features.OpenAPIV3) {
				openapiv3Controller := openapiv3controller.NewController(s.Informers.Apiextensions().V1().CustomResourceDefinitions())
				go openapiv3Controller.Run(s.GenericAPIServer.OpenAPIV3VersionedService, context.StopCh)
			}
		}

		go namingController.Run(context.StopCh)
		go establishingController.Run(context.StopCh)
		go nonStructuralSchemaController.Run(5, context.StopCh)
		go apiApprovalController.Run(5, context.StopCh)
		go finalizingController.Run(5, context.StopCh)

		discoverySyncedCh := make(chan struct{})
		go discoveryController.Run(context.StopCh, discoverySyncedCh)
		select {
		case <-context.StopCh:
		case <-discoverySyncedCh:
		}

		return nil
	})
	// we don't want to report healthy until we can handle all CRDs that have already been registered.  Waiting for the informer
	// to sync makes sure that the lister will be valid before we begin.  There may still be races for CRDs added after startup,
	// but we won't go healthy until we can handle the ones already present.
	s.GenericAPIServer.AddPostStartHookOrDie("crd-informer-synced", func(context genericapiserver.PostStartHookContext) error {
		return wait.PollImmediateUntil(100*time.Millisecond, func() (bool, error) {
			if s.Informers.Apiextensions().V1().CustomResourceDefinitions().Informer().HasSynced() {
				close(hasCRDInformerSyncedSignal)
				return true, nil
			}
			return false, nil
		}, context.StopCh)
	})

	return s, nil
}


// 路由注册
// s.GenericAPIServer.InstallAPIGroup(&apiGroupInfo)
func (s *GenericAPIServer) InstallAPIGroup(apiGroupInfo *APIGroupInfo) error {
	return s.InstallAPIGroups(apiGroupInfo)
}
func (s *GenericAPIServer) InstallAPIGroups(apiGroupInfos ...*APIGroupInfo) error {
    // 教研

	openAPIModels, err := s.getOpenAPIModels(APIGroupPrefix, apiGroupInfos...)

	for _, apiGroupInfo := range apiGroupInfos {
		s.installAPIResources(APIGroupPrefix, apiGroupInfo, openAPIModels) // apiGroupInfo相当于一个中间临时变量，用来生成APIGroupVersion 

		// setup discovery
		// Install the version handler.
		// Add a handler at /apis/<groupName> to enumerate all versions supported by this group.
		apiGroup := metav1.APIGroup{
			Name:             apiGroupInfo.PrioritizedVersions[0].Group,
			Versions:         apiVersionsForDiscovery,
			PreferredVersion: preferredVersionForDiscovery,
		}
		s.DiscoveryGroupManager.AddGroup(apiGroup)
        // 这个 /apis/<apigroup>/ 打印apigroupinfo
		s.Handler.GoRestfulContainer.Add(discovery.NewAPIGroupHandler(s.Serializer, apiGroup).WebService())
	}
	return nil
}

// installAPIResources is a private method for installing the REST storage backing each api groupversionresource
// apiPrefix = apis , typeConverter = openAPIModels
func (s *GenericAPIServer) installAPIResources(apiPrefix string, apiGroupInfo *APIGroupInfo, typeConverter managedfields.TypeConverter) error {
	var resourceInfos []*storageversion.ResourceInfo
	for _, groupVersion := range apiGroupInfo.PrioritizedVersions { // 按照优先级注册
        // 只注册有存储的groupversion
		if len(apiGroupInfo.VersionedResourcesStorageMap[groupVersion.Version]) == 0 { continue }

		apiGroupVersion, err := s.getAPIGroupVersion(apiGroupInfo, groupVersion, apiPrefix) // APIGroupVersion是用来辅助restful请求的
		if err != nil {
			return err
		}
		if apiGroupInfo.OptionsExternalVersion != nil {
			apiGroupVersion.OptionsExternalVersion = apiGroupInfo.OptionsExternalVersion
		}
		apiGroupVersion.TypeConverter = typeConverter
		apiGroupVersion.MaxRequestBodyBytes = s.maxRequestBodyBytes

		discoveryAPIResources, r, err := apiGroupVersion.InstallREST(s.Handler.GoRestfulContainer)

		if err != nil {
			return fmt.Errorf("unable to setup API %v: %v", apiGroupInfo, err)
		}
		resourceInfos = append(resourceInfos, r...)

		if utilfeature.DefaultFeatureGate.Enabled(features.AggregatedDiscoveryEndpoint) {
			// Aggregated discovery only aggregates resources under /apis
			if apiPrefix == APIGroupPrefix {
				s.AggregatedDiscoveryGroupManager.AddGroupVersion(
					groupVersion.Group,
					apidiscoveryv2beta1.APIVersionDiscovery{
						Freshness: apidiscoveryv2beta1.DiscoveryFreshnessCurrent,
						Version:   groupVersion.Version,
						Resources: discoveryAPIResources,
					},
				)
			} else {
				// There is only one group version for legacy resources, priority can be defaulted to 0.
				s.AggregatedLegacyDiscoveryGroupManager.AddGroupVersion(
					groupVersion.Group,
					apidiscoveryv2beta1.APIVersionDiscovery{
						Freshness: apidiscoveryv2beta1.DiscoveryFreshnessCurrent,
						Version:   groupVersion.Version,
						Resources: discoveryAPIResources,
					},
				)
			}
		}

	}

	s.RegisterDestroyFunc(apiGroupInfo.destroyStorage)

	if utilfeature.DefaultFeatureGate.Enabled(features.StorageVersionAPI) &&
		utilfeature.DefaultFeatureGate.Enabled(features.APIServerIdentity) {
		// API installation happens before we start listening on the handlers,
		// therefore it is safe to register ResourceInfos here. The handler will block
		// write requests until the storage versions of the targeting resources are updated.
		s.StorageVersionManager.AddResourceInfo(resourceInfos...)
	}

	return nil
}
// getAPIGreoupVersion
func (s *GenericAPIServer) getAPIGroupVersion(apiGroupInfo *APIGroupInfo, groupVersion schema.GroupVersion, apiPrefix string) (*genericapi.APIGroupVersion, error) {
	storage := make(map[string]rest.Storage)
	for k, v := range apiGroupInfo.VersionedResourcesStorageMap[groupVersion.Version] { // k = version , v is map
		storage[k] = v
	}
	version := s.newAPIGroupVersion(apiGroupInfo, groupVersion)
	version.Root = apiPrefix
	version.Storage = storage
	return version, nil
}
// generic APIGroupVersion 结构体
// APIGroupVersion 
// APIGroupVersion is a helper for exposing rest.Storage objects as http.Handlers via go-restful
// It handles URLs of the form:
// /${storage_key}[/${object_name}]
// Where 'storage_key' points to a rest.Storage object stored in storage.
// This object should contain all parameterization necessary for running a particular API version
type APIGroupVersion struct {
	Storage map[string]rest.Storage

	Root string

	// GroupVersion is the external group version
	GroupVersion schema.GroupVersion

	// AllServedVersionsByResource is indexed by resource and maps to a list of versions that resource exists in.
	// This was created so that StorageVersion for APIs can include a list of all version that are served for each
	// GroupResource tuple.
	AllServedVersionsByResource map[string][]string

	// OptionsExternalVersion controls the Kubernetes APIVersion used for common objects in the apiserver
	// schema like api.Status, api.DeleteOptions, and metav1.ListOptions. Other implementors may
	// define a version "v1beta1" but want to use the Kubernetes "v1" internal objects. If
	// empty, defaults to GroupVersion.
	OptionsExternalVersion *schema.GroupVersion
	// MetaGroupVersion defaults to "meta.k8s.io/v1" and is the scheme group version used to decode
	// common API implementations like ListOptions. Future changes will allow this to vary by group
	// version (for when the inevitable meta/v2 group emerges).
	MetaGroupVersion *schema.GroupVersion

	// RootScopedKinds are the root scoped kinds for the primary GroupVersion
	RootScopedKinds sets.String

	// Serializer is used to determine how to convert responses from API methods into bytes to send over
	// the wire.
	Serializer     runtime.NegotiatedSerializer
	ParameterCodec runtime.ParameterCodec

	Typer                 runtime.ObjectTyper
	Creater               runtime.ObjectCreater
	Convertor             runtime.ObjectConvertor
	ConvertabilityChecker ConvertabilityChecker
	Defaulter             runtime.ObjectDefaulter
	Namer                 runtime.Namer
	UnsafeConvertor       runtime.ObjectConvertor
	TypeConverter         managedfields.TypeConverter

	EquivalentResourceRegistry runtime.EquivalentResourceRegistry

	// Authorizer determines whether a user is allowed to make a certain request. The Handler does a preliminary
	// authorization check using the request URI but it may be necessary to make additional checks, such as in
	// the create-on-update case
	Authorizer authorizer.Authorizer

	Admit admission.Interface

	MinRequestTimeout time.Duration

	// The limit on the request body size that would be accepted and decoded in a write request.
	// 0 means no limit.
	MaxRequestBodyBytes int64
}
```



```go 
// scope request相关用到的工具
func createHandler(r rest.NamedCreater, scope *RequestScope, admit admission.Interface, includeName bool) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		namespace, name, err := scope.Namer.Name(req)

		// enforce a timeout of at most requestTimeoutUpperBound (34s) or less if the user-provided
		// timeout inside the parent context is lower than requestTimeoutUpperBound.
		outputMediaType, _, err := negotiation.NegotiateOutputMediaType(req, scope.Serializer, scope)

		gv := scope.Kind.GroupVersion()
		s, err := negotiation.NegotiateInputSerializer(req, false, scope.Serializer)

        // read body
		body, err := limitedReadBodyWithRecordMetric(ctx, req, scope.MaxRequestBodyBytes, scope.Resource.GroupResource().String(), requestmetrics.Create)
		if err != nil {
			span.AddEvent("limitedReadBody failed", attribute.Int("len", len(body)), attribute.String("err", err.Error()))
			scope.err(err, w, req)
			return
		}
		span.AddEvent("limitedReadBody succeeded", attribute.Int("len", len(body)))

		options := &metav1.CreateOptions{}
		values := req.URL.Query()
        // decode json into metaobject
		metainternalversionscheme.ParameterCodec.DecodeParameters(values, scope.MetaGroupVersion, options)

		options.TypeMeta.SetGroupVersionKind(metav1.SchemeGroupVersion.WithKind("CreateOptions"))

		defaultGVK := scope.Kind // input version/ external version
		original := r.New() // stroage.New() 通过scheme 来获取一个Object

		validationDirective := fieldValidation(options.FieldValidation)

		decodeSerializer := s.Serializer
		if validationDirective == metav1.FieldValidationWarn || validationDirective == metav1.FieldValidationStrict {
			decodeSerializer = s.StrictSerializer
		}

		decoder := scope.Serializer.DecoderToVersion(decodeSerializer, scope.HubGroupVersion)
		span.AddEvent("About to convert to expected version")
        // decode into external version
		obj, gvk, err := decoder.Decode(body, &defaultGVK, original)
		if err != nil {
			strictError, isStrictError := runtime.AsStrictDecodingError(err)
			switch {
			case isStrictError && obj != nil && validationDirective == metav1.FieldValidationWarn:
				addStrictDecodingWarnings(req.Context(), strictError.Errors())
			case isStrictError && validationDirective == metav1.FieldValidationIgnore:
				klog.Warningf("unexpected strict error when field validation is set to ignore")
				fallthrough
			default:
				err = transformDecodeError(scope.Typer, err, original, gvk, body)
				scope.err(err, w, req)
				return
			}
		}

		objGV := gvk.GroupVersion()
		if !scope.AcceptsGroupVersion(objGV) {
			err = errors.NewBadRequest(fmt.Sprintf("the API version in the data (%s) does not match the expected API version (%v)", objGV.String(), gv.String()))
			scope.err(err, w, req)
			return
		}
		span.AddEvent("Conversion done")

		// On create, get name from new object if unset
		if len(name) == 0 {
			_, name, _ = scope.Namer.ObjectName(obj)
		}
		if len(namespace) == 0 && scope.Resource == namespaceGVR {
			namespace = name
		}
		ctx = request.WithNamespace(ctx, namespace)

		admit = admission.WithAudit(admit)
		audit.LogRequestObject(req.Context(), obj, objGV, scope.Resource, scope.Subresource, scope.Serializer)

		userInfo, _ := request.UserFrom(ctx)

		if objectMeta, err := meta.Accessor(obj); err == nil {
			preserveObjectMetaSystemFields := false
			if c, ok := r.(rest.SubresourceObjectMetaPreserver); ok && len(scope.Subresource) > 0 {
				preserveObjectMetaSystemFields = c.PreserveRequestObjectMetaSystemFieldsOnSubresourceCreate()
			}
			if !preserveObjectMetaSystemFields {
				rest.WipeObjectMetaSystemFields(objectMeta)
			}

			// ensure namespace on the object is correct, or error if a conflicting namespace was set in the object
			if err := rest.EnsureObjectNamespaceMatchesRequestNamespace(rest.ExpectedNamespaceForResource(namespace, scope.Resource), objectMeta); err != nil {
				scope.err(err, w, req)
				return
			}
		}

		span.AddEvent("About to store object in database")
		admissionAttributes := admission.NewAttributesRecord(obj, nil, scope.Kind, namespace, name, scope.Resource, scope.Subresource, admission.Create, options, dryrun.IsDryRun(options.DryRun), userInfo)
		requestFunc := func() (runtime.Object, error) {
			return r.Create(
				ctx,
				name,
				obj,
				rest.AdmissionToValidateObjectFunc(admit, admissionAttributes, scope),
				options,
			)
		}
		// Dedup owner references before updating managed fields
		dedupOwnerReferencesAndAddWarning(obj, req.Context(), false)
		result, err := finisher.FinishRequest(ctx, func() (runtime.Object, error) {
			liveObj, err := scope.Creater.New(scope.Kind)
			if err != nil {
				return nil, fmt.Errorf("failed to create new object (Create for %v): %v", scope.Kind, err)
			}
			obj = scope.FieldManager.UpdateNoErrors(liveObj, obj, managerOrUserAgent(options.FieldManager, req.UserAgent()))
			admit = fieldmanager.NewManagedFieldsValidatingAdmissionController(admit)

			if mutatingAdmission, ok := admit.(admission.MutationInterface); ok && mutatingAdmission.Handles(admission.Create) {
				if err := mutatingAdmission.Admit(ctx, admissionAttributes, scope); err != nil {
					return nil, err
				}
			}
			// Dedup owner references again after mutating admission happens
			dedupOwnerReferencesAndAddWarning(obj, req.Context(), true)
			result, err := requestFunc()
			// If the object wasn't committed to storage because it's serialized size was too large,
			// it is safe to remove managedFields (which can be large) and try again.
			if isTooLargeError(err) {
				if accessor, accessorErr := meta.Accessor(obj); accessorErr == nil {
					accessor.SetManagedFields(nil)
					result, err = requestFunc()
				}
			}
			return result, err
		})
		if err != nil {
			span.AddEvent("Write to database call failed", attribute.Int("len", len(body)), attribute.String("err", err.Error()))
			scope.err(err, w, req)
			return
		}
		span.AddEvent("Write to database call succeeded", attribute.Int("len", len(body)))

		code := http.StatusCreated
		status, ok := result.(*metav1.Status)
		if ok && status.Code == 0 {
			status.Code = int32(code)
		}

		span.AddEvent("About to write a response")
		defer span.AddEvent("Writing http response done")
		transformResponseObject(ctx, scope, req, w, code, outputMediaType, result)
	}
}
```



