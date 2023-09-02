```go
// 
	controlPlane, serviceResolver, pluginInitializer, err := CreateKubeAPIServerConfig(opts)
```

&emsp;`Complete`完成哪些事情?  Option处理阶段
```go
// 1. 解析Adversit address, ApiService Ipaddress
	s.PrimaryServiceClusterIPRange = primaryServiceIPRange
	s.SecondaryServiceClusterIPRange = secondaryServiceIPRange
	s.APIServerServiceIP = apiServerServiceIP

// 2. 生成apiserver的tls证书,如果有提供tls这个参数则使用tls证书,如果没有则生成一个自签证书
    s.Authentication.ServiceAccount = sa_tls || apiserver_tls

// 根据Authroization的一些安全设置，更新authentication的配置(默认AlwaysAllow)如果都允许不做任何authori, 那么就不允许匿名登陆(不然就等同于任何人无限制的访问)
	s.Authentication.ApplyAuthorization(s.Authorization)

// 
    s.Authentication.ServiceAccount = 认证信息(如果sa-signer提供证书则使用,如果没有则使用apisever的tls证书)
```


&emsp;`NewConfig`做了哪些事情? 根据Option来生成配置文件,并且填充默认值, 代码位置`cmd/kube-apiserver/app.server.go:func Run(xxx, xxx)`
```go 
// 整体代码结构
    // kube-apiserver 配置
	controlPlane, serviceResolver, pluginInitializer, err := CreateKubeAPIServerConfig(opts)

    // apiextensiuonServer config
	apiExtensions, err := apiserver.CreateAPIExtensionsConfig(*controlPlane.GenericConfig, controlPlane.ExtraConfig.VersionedInformers, pluginInitializer, opts.ServerRunOptions, opts.MasterCount,
		serviceResolver, webhook.NewDefaultAuthenticationInfoResolverWrapper(controlPlane.ExtraConfig.ProxyTransport, controlPlane.GenericConfig.EgressSelector, controlPlane.GenericConfig.LoopbackClientConfig, controlPlane.GenericConfig.TracerProvider))

    // aggregator Server config
	aggregator, err := createAggregatorConfig(*controlPlane.GenericConfig, opts.ServerRunOptions, controlPlane.ExtraConfig.VersionedInformers, serviceResolver, controlPlane.ExtraConfig.ProxyTransport, pluginInitializer)
```

&emsp; `kubeapiserver` config 逻辑 ,kubeapiserver这部分主要拆分2块, 一块是创建genericApiserver 的配置文件(这一部分是一个APIserver所必备的一些元素), 另外一部分是各自apiserver针对自己具体提供的功能/服务的apigroup做的一些特色的配置; 其实通用配置文件也有2部分(1. )
```go
// Apiserver Config (Generic Apiserver Config)
    // ApiServer 包装了 controlplaneapiserever, contoleplaneapiserver 包装了generic apiserver
	genericConfig, versionedInformers, storageFactory, err := controlplaneapiserver.BuildGenericConfig(
		s.ServerRunOptions,
		[]*runtime.Scheme{legacyscheme.Scheme, extensionsapiserver.Scheme, aggregatorscheme.Scheme},
		generatedopenapi.GetOpenAPIDefinitions,
	)
    {
        // 每个集群都有一个唯一的表识
        config = Config{APIServerID: apiserverId}
	    if lastErr = s.GenericServerRunOptions.ApplyTo(genericConfig); lastErr != nil {/* 根据ServverRunOpts 选项来填充Config相关字段*/}
	    if lastErr = s.Features.ApplyTo(genericConfig); lastErr != nil { /* 根据Opts里面一些feature设置config相关feature字段*/}
        // ......

        // storageConfig 逻辑是如下 kubeapiserver.default_factory_bulder -> kubeapiserver.default_factory_bulder.completedConfig -> k8s.io/apiserver/pkg/server/storage/storage_factory.DefaultStorageFactory
	    storageFactoryConfig := kubeapiserver.NewStorageFactoryConfig()
	    storageFactoryConfig.APIResourceConfig = genericConfig.MergedResourceConfig
	    storageFactory, lastErr = storageFactoryConfig.Complete(s.Etcd).New()
	    if lastErr != nil {
	    	return
	    }
	    if lastErr = s.Etcd.ApplyWithStorageFactoryTo(storageFactory, genericConfig); lastErr != nil {
	    	return
	    }
        // ........

        
        // genericConfig.Authentication.Authenticator.AuthenticateRequest(req *http.Request) 效果这行代码
	    if lastErr = s.Authentication.ApplyTo(&genericConfig.Authentication, genericConfig.SecureServing, genericConfig.EgressSelector, genericConfig.OpenAPIConfig, genericConfig.OpenAPIV3Config, clientgoExternalClient, versionedInformers); lastErr != nil {
            // 
	    	return
	    }

        // genericConfig.Authorization.Authorizer.Authorize(ctx context.Context, a authorizer.Attributes)
	    genericConfig.Authorization.Authorizer, genericConfig.RuleResolver, err = BuildAuthorizer(s, genericConfig.EgressSelector, versionedInformers)

        // genericConfig.AuditBackend.ProcessEvents(events ...*audit.Event) 效果
	    lastErr = s.Audit.ApplyTo(genericConfig)

	    if utilfeature.DefaultFeatureGate.Enabled(genericfeatures.APIPriorityAndFairness) && s.GenericServerRunOptions.EnablePriorityAndFairness {
	    	genericConfig.FlowControl, lastErr = BuildPriorityAndFairness(s, clientgoExternalClient, versionedInformers)
	    }

	    if utilfeature.DefaultFeatureGate.Enabled(genericfeatures.AggregatedDiscoveryEndpoint) {
	    	genericConfig.AggregatedDiscoveryGroupManager = aggregated.NewResourceManager("apis")
	    }

    }




```

&emsp;`kube-apiserver config`



&emsp;`api-extension server config`



&emsp;`aggregatedApiserver config`

