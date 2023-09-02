&emsp;`AdmissionOptions` 声明如下
```go 
// AdmissionOptions holds the admission options
type AdmissionOptions struct {
	// RecommendedPluginOrder holds an ordered list of plugin names we recommend to use by default, 推荐插件顺序,用户调用的时候根据这个顺序来调用插件
	RecommendedPluginOrder []string
	// DefaultOffPlugins is a set of plugin names that is disabled by default// 被禁用的plugins
	DefaultOffPlugins sets.String

	// EnablePlugins indicates plugins to be enabled passed through `--enable-admission-plugins`. // 通过 cli 传递过去的插件名称， 最终会merge
	EnablePlugins []string
	// DisablePlugins indicates plugins to be disabled passed through `--disable-admission-plugins`. // 通过cli 禁用的插件名称  最终会merge
	DisablePlugins []string
	// ConfigFile is the file path with admission control configuration.
	ConfigFile string  // 
	// Plugins contains all registered plugins.
	Plugins *admission.Plugins   //  plugin registry, 所有注册的plugin都放在这个里面
	// Decorators is a list of admission decorator to wrap around the admission plugins
	Decorators admission.Decorators
}
```

&emsp; 创建AdmissionOptions
```go 
func NewAdmissionOptions() *AdmissionOptions {
	options := genericoptions.NewAdmissionOptions()
	// register all admission plugins
	RegisterAllAdmissionPlugins(options.Plugins)
	// set RecommendedPluginOrder
	options.RecommendedPluginOrder = AllOrderedPlugins
	// set DefaultOffPlugins
	options.DefaultOffPlugins = DefaultOffAdmissionPlugins()

	return &AdmissionOptions{
		GenericAdmission: options,
	}
}
// 创建一个admission options ，这个暂时把它当作一个map来看就行了map[pluginStr]AdmissionInterface, AdmissionInterface实现了Handles(Operation)方法
// 所以最终插件调用伪代码如下for plugin in allRegisterPlugins { plugin.Handlers(Op)}
func NewAdmissionOptions() *AdmissionOptions {
	options := &AdmissionOptions{
		Plugins:    admission.NewPlugins(),  // 其实就是创建Plugins结构体 Plugins: Plugins {lock, registry: map[string]Factory}
        // Decorators: []Decorator,是一个接口的`Decorator` slice, 用于创建Interface (Interface实现Handler的接口), 所以默认情况下我们只需要查看WithControllerMetric 这个handler是干啥的就行了
		Decorators: admission.Decorators{admission.DecoratorFunc(admissionmetrics.WithControllerMetrics)},
		// This list is mix of mutating admission plugins and validating
		// admission plugins. The apiserver always runs the validating ones
		// after all the mutating ones, so their relative order in this list
		// doesn't matter.
        // 默认顺序如下lifecycle.Plugin, mutatingwebhooks , validatingadmissionpolicy, validatingwebhooks
		RecommendedPluginOrder: []string{lifecycle.PluginName, mutatingwebhook.PluginName, validatingadmissionpolicy.PluginName, validatingwebhook.PluginName},
		DefaultOffPlugins:      sets.NewString(),
	}
	server.RegisterAllAdmissionPlugins(options.Plugins)
	return options
}

// plugin定义如下
type Factory func(config io.Reader) (Interface, error)

type Plugins struct {
	lock     sync.Mutex
	registry map[string]Factory
}

func NewPlugins() *Plugins {
	return &Plugins{}
}
// Decorator 的接口如下
func (d Decorators) Decorate(handler Interface, name string) Interface {
	result := handler
	for _, d := range d {
		result = d.Decorate(result, name)
	}
	return result
}
// WithControllerMetrics is a decorator for named admission handlers.
func WithControllerMetrics(i admission.Interface, name string) admission.Interface {
	return WithMetrics(i, Metrics.ObserveAdmissionController, name)
}

// 注册所有的AdmissionPlugins

```

&emsp;默认注册的插件
```go

func RegisterAllAdmissionPlugins(plugins *admission.Plugins) {
	lifecycle.Register(plugins) // plugin.Register()
	validatingwebhook.Register(plugins) // plugin.Register
	mutatingwebhook.Register(plugins)
	validatingadmissionpolicy.Register(plugins)
}


// 通用注册逻辑如下
func (ps *Plugins) Register(name string, plugin Factory) {
    // ....
	ps.registry[name] = plugin
    // instancePlugin = plugin()
    // instancePlugin.Handles(action)
}


```
// k8s.io/apiserver/pkg/server/plugins.go

&emsp;`lifecycle`plugin
```go 
func Register(plugins *admission.Plugins) {
	plugins.Register("NamespaceLifecycle", func(config io.Reader) (admission.Interface, error) {
		return NewLifecycle(sets.NewString(metav1.NamespaceDefault, metav1.NamespaceSystem, metav1.NamespacePublic))
	})
}
func NewLifecycle(immortalNamespaces sets.String) (*Lifecycle, error) {
	return newLifecycleWithClock(immortalNamespaces, clock.RealClock{})
}
func newLifecycleWithClock(immortalNamespaces sets.String, clock utilcache.Clock) (*Lifecycle, error) {
	forceLiveLookupCache := utilcache.NewLRUExpireCacheWithClock(100, clock)
	return &Lifecycle{
		Handler:              admission.NewHandler(admission.Create, admission.Update, admission.Delete),
		immortalNamespaces:   immortalNamespaces, //{public, kube-system, kube-public}
		forceLiveLookupCache: forceLiveLookupCache,
	}, nil
}

func NewHandler(ops ...Operation) *Handler {
    // ...
	return &Handler{
		operations: ops,
	}
}
// 所以lifecycle 验证逻辑只能执行create update, delete 操作
func (h *Handler) Handles(operation Operation) bool {
	return h.operations.Has(string(operation))
}


```

&emsp;`validating webhooks` plugin

&emsp;`mutating webhooks` plugin

&emsp;`validating admission policy` plugin




#### 创建Admission
```go 

	// setup admission
	admissionConfig := &kubeapiserveradmission.Config{
		ExternalInformers:    versionedInformers,
		LoopbackClientConfig: genericConfig.LoopbackClientConfig,
		CloudConfigFile:      opts.CloudProvider.CloudConfigFile,
	}
    // serviceResolver 将k8s service解析成 url
	serviceResolver := buildServiceResolver(opts.EnableAggregatorRouting, genericConfig.LoopbackClientConfig.Host, versionedInformers)

	pluginInitializers, admissionPostStartHook, err := admissionConfig.New(proxyTransport, genericConfig.EgressSelector, serviceResolver, genericConfig.TracerProvider)

	err = opts.Admission.ApplyTo(
		genericConfig, // apiserver config
		versionedInformers, // sharedInformer
		clientgoExternalClient, // loopclient 
		dynamicExternalClient, // loop client
		utilfeature.DefaultFeatureGate, 
		pluginInitializers...)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("failed to apply admission: %w", err)
	}


// 
```

&emsp;pluginInitializer 创建一个空的pluginiInitializer 
```go 
// New sets up the plugins and admission start hooks needed for admission
func (c *Config) New(proxyTransport *http.Transport, egressSelector *egressselector.EgressSelector, serviceResolver webhook.ServiceResolver, tp trace.TracerProvider) ([]admission.PluginInitializer, genericapiserver.PostStartHookFunc, error) {
	webhookAuthResolverWrapper := webhook.NewDefaultAuthenticationInfoResolverWrapper(proxyTransport, egressSelector, c.LoopbackClientConfig, tp)
	webhookPluginInitializer := webhookinit.NewPluginInitializer(webhookAuthResolverWrapper, serviceResolver)

    // clientset
	kubePluginInitializer := NewPluginInitializer( cloudConfig, discoveryRESTMapper, quotainstall.NewQuotaConfigurationForAdmission(),)

	return []admission.PluginInitializer{webhookPluginInitializer, kubePluginInitializer}, admissionPostStartHook, nil
}

// AuthenticationinfoResoluver  用来构建restConfig根据server或者service.name + service.namespace
// webhooksAuthResolverWrapper
func NewDefaultAuthenticationInfoResolverWrapper( proxyTransport *http.Transport, egressSelector *egressselector.EgressSelector, kubeapiserverClientConfig *rest.Config, tp trace.TracerProvider) AuthenticationInfoResolverWrapper {
	webhookAuthResolverWrapper := func(delegate AuthenticationInfoResolver) AuthenticationInfoResolver {
        // AuthenticationInfoResoluverDelegator impl AuthenticationInfoResolver 
		return &AuthenticationInfoResolverDelegator{
			ClientConfigForFunc: func(hostPort string) (*rest.Config, error) {
                // 根据 host port 来生成配置文件
				return ret, nil
			},
			ClientConfigForServiceFunc: func(serviceName, serviceNamespace string, servicePort int) (*rest.Config, error) {
                // 根据service name + service namespace 来生成配置文件
				return ret, nil
			},
		}
	}
	return webhookAuthResolverWrapper
}


// webhookPluginInitializer 
// NewPluginInitializer constructs new instance of PluginInitializer
func NewPluginInitializer( authenticationInfoResolverWrapper webhook.AuthenticationInfoResolverWrapper, serviceResolver webhook.ServiceResolver,) *PluginInitializer {
	return &PluginInitializer{
		authenticationInfoResolverWrapper: authenticationInfoResolverWrapper, // 一个提供客户端
		serviceResolver:                   serviceResolver, // 一个提供URL解析
	}
}

// plugin initializer 
func NewPluginInitializer( cloudConfig []byte, restMapper meta.RESTMapper, quotaConfiguration quota.Configuration,) *PluginInitializer {
	return &PluginInitializer{
		cloudConfig:        cloudConfig, // cloud配置文件
		restMapper:         restMapper, // restmapper 提供 gvk -> gkr映射
		quotaConfiguration: quotaConfiguration,
	}
}

```


#### 创建PluginChain
```go 
func (a *AdmissionOptions) ApplyTo( c *server.Config, informers informers.SharedInformerFactory, kubeClient kubernetes.Interface, dynamicClient dynamic.Interface, features featuregate.FeatureGate, pluginInitializers ...admission.PluginInitializer,) error {
    // ....
	return a.GenericAdmission.ApplyTo(c, informers, kubeClient, dynamicClient, features, pluginInitializers...)
}


func (a *AdmissionOptions) ApplyTo( c *server.Config, informers informers.SharedInformerFactory, kubeClient kubernetes.Interface, dynamicClient dynamic.Interface, features featuregate.FeatureGate, pluginInitializers ...admission.PluginInitializer,) error {

	pluginNames := a.enabledPluginNames()

    // pluginConfigProvider create plugin from config

	genericInitializer := initializer.New(kubeClient, dynamicClient, informers, c.Authorization.Authorizer, features, c.DrainedNotify())

    // initializerChian := PluginInitizlizers{}  //  []PlugonInitialize //  for _, p := range []PluginInitializer {p.Initialize()}
	initializersChain := admission.PluginInitializers{genericInitializer, webhookPluginInitializer, kubePluginInitializer}

	admissionChain, err := a.Plugins.NewFromPlugins(pluginNames, pluginsConfigProvider, initializersChain, a.Decorators)
    // admissionChain, err :=  reinvoker{handlers}
	if err != nil {
		return err
	}

	c.AdmissionControl = admissionmetrics.WithStepMetrics(admissionChain)
    // 本质上c.AdmissionControl 就wrap了下 reinvoker{handlers}
	return nil
}



// 根据
func (ps *Plugins) NewFromPlugins(pluginNames []string, configProvider ConfigProvider, pluginInitializer PluginInitializer, decorator Decorator) (Interface, error) {
	handlers := []Interface{}
	for _, pluginName := range pluginNames {
		pluginConfig, err := configProvider.ConfigFor(pluginName) // nil, nil

		plugin, err := ps.InitPlugin(pluginName, pluginConfig, pluginInitializer) // 根据插件配置实例化具体插件 // plugin.setSomeAuthOptions()

		if plugin != nil {
			handlers = append(handlers, decorator.Decorate(plugin, pluginName))
		}
	}
    // ..会统计下mutationPlugin和validating Plugin 打印信息
    return reinvoker{handlers} // reinvoker 实现了admissionChain 的接口
	// return newReinvocationHandler(chainAdmissionHandler(handlers)), nil
}

// 实例化插件
func (ps *Plugins) InitPlugin(name string, config io.Reader, pluginInitializer PluginInitializer) (Interface, error) {
    // 根据插件名称获取
	plugin, found, err := ps.getPlugin(name, config) // plugin,found, err := ps.registry[name]

	pluginInitializer.Initialize(plugin) // 
    /*
    for _, p := range []{genericInitializer, webhooksPluginInitializer, kubePluginInitializer} {
        p.Initialize(plugin)
    }
    */

	return plugin, nil
}


// genericPlugin的Initialize方法 通用插件初始化
func (i pluginInitializer) Initialize(plugin admission.Interface) {
	// First tell the plugin about drained notification, so it can pass it to further initializations.
	if wants, ok := plugin.(WantsDrainedNotification); ok {
		wants.SetDrainedNotification(i.stopCh)
	}

	// Second tell the plugin about enabled features, so it can decide whether to start informers or not
	if wants, ok := plugin.(WantsFeatures); ok {
		wants.InspectFeatureGates(i.featureGates)
	}

	if wants, ok := plugin.(WantsExternalKubeClientSet); ok {
		wants.SetExternalKubeClientSet(i.externalClient)
	}

	if wants, ok := plugin.(WantsDynamicClient); ok {
		wants.SetDynamicClient(i.dynamicClient)
	}

	if wants, ok := plugin.(WantsExternalKubeInformerFactory); ok {
		wants.SetExternalKubeInformerFactory(i.externalInformers)
	}

	if wants, ok := plugin.(WantsAuthorizer); ok {
		wants.SetAuthorizer(i.authorizer)
	}
}



// webhook plugin Initialize 方法 调用webhook时候会调用serviceResolver 来生成http 的url, 根据authenticationInfoResolver 来获取client的config 两个组合到一起就可以发起http请求
func (i *PluginInitializer) Initialize(plugin admission.Interface) {
	if wants, ok := plugin.(WantsServiceResolver); ok {
		wants.SetServiceResolver(i.serviceResolver)
	}
	if wants, ok := plugin.(WantsAuthenticationInfoResolverWrapper); ok {
		if i.authenticationInfoResolverWrapper != nil {
			wants.SetAuthenticationInfoResolverWrapper(i.authenticationInfoResolverWrapper)
		}
	}
}


// KubePlugin Initialize方法 kubernetes Plugin 主要针对云环境
func (i *PluginInitializer) Initialize(plugin admission.Interface) {
	if wants, ok := plugin.(WantsCloudConfig); ok {
		wants.SetCloudConfig(i.cloudConfig)
	}

	if wants, ok := plugin.(initializer.WantsRESTMapper); ok {
		wants.SetRESTMapper(i.restMapper)
	}

	if wants, ok := plugin.(initializer.WantsQuotaConfiguration); ok {
		wants.SetQuotaConfiguration(i.quotaConfiguration)
	}
}

```


#### Admission执行



