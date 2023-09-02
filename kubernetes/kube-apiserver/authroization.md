&emsp;`Authorization` options如下
```go
// BuiltInAuthorizationOptions contains all build-in authorization options for API Server
type BuiltInAuthorizationOptions struct {
	Modes                       []string
	PolicyFile                  string
	WebhookConfigFile           string
	WebhookVersion              string
	WebhookCacheAuthorizedTTL   time.Duration
	WebhookCacheUnauthorizedTTL time.Duration
	// WebhookRetryBackoff specifies the backoff parameters for the authorization webhook retry logic.
	// This allows us to configure the sleep time at each iteration and the maximum number of retries allowed
	// before we fail the webhook call in order to limit the fan out that ensues when the system is degraded.
	WebhookRetryBackoff *wait.Backoff
}

// NewBuiltInAuthorizationOptions create a BuiltInAuthorizationOptions with default value
func NewBuiltInAuthorizationOptions() *BuiltInAuthorizationOptions {
	return &BuiltInAuthorizationOptions{
		Modes:                       []string{authzmodes.ModeAlwaysAllow},
		WebhookVersion:              "v1beta1",
		WebhookCacheAuthorizedTTL:   5 * time.Minute,
		WebhookCacheUnauthorizedTTL: 30 * time.Second,
		WebhookRetryBackoff:         genericoptions.DefaultAuthWebhookRetryBackoff(),
	}
}
```


#### 构建Authorizer 
```go 
	// genericConfig.Authorization.Authorizer, genericConfig.RuleResolver, err = BuildAuthorizer(s, genericConfig.EgressSelector, versionedInformers)

// BuildAuthorizer constructs the authorizer
func BuildAuthorizer(s controlplaneapiserver.CompletedOptions, EgressSelector *egressselector.EgressSelector, versionedInformers clientgoinformers.SharedInformerFactory) (authorizer.Authorizer, authorizer.RuleResolver, error) {
	authorizationConfig := s.Authorization.ToAuthorizationConfig(versionedInformers) // authorizationConfig = &authorizer.Config{}

    // .....
	return authorizationConfig.New()
}



// 生成配置
func (o *BuiltInAuthorizationOptions) ToAuthorizationConfig(versionedInformerFactory versionedinformers.SharedInformerFactory) authorizer.Config {
	return authorizer.Config{
		AuthorizationModes:          o.Modes,
		PolicyFile:                  o.PolicyFile,
		WebhookConfigFile:           o.WebhookConfigFile,
		WebhookVersion:              o.WebhookVersion,
		WebhookCacheAuthorizedTTL:   o.WebhookCacheAuthorizedTTL,
		WebhookCacheUnauthorizedTTL: o.WebhookCacheUnauthorizedTTL,
		VersionedInformerFactory:    versionedInformerFactory,
		WebhookRetryBackoff:         o.WebhookRetryBackoff,
	}
}


func (config Config) New() (authorizer.Authorizer, authorizer.RuleResolver, error) {
	if len(config.AuthorizationModes) == 0 {
		return nil, nil, fmt.Errorf("at least one authorization mode must be passed")
	}

	var (
		authorizers   []authorizer.Authorizer
		ruleResolvers []authorizer.RuleResolver
	)

	// Add SystemPrivilegedGroup as an authorizing group
	superuserAuthorizer := authorizerfactory.NewPrivilegedGroups(user.SystemPrivilegedGroup)
	authorizers = append(authorizers, superuserAuthorizer)

	for _, authorizationMode := range config.AuthorizationModes {
		// Keep cases in sync with constant list in k8s.io/kubernetes/pkg/kubeapiserver/authorizer/modes/modes.go.
		switch authorizationMode {
		case modes.ModeNode:
			graph := node.NewGraph()
			node.AddGraphEventHandlers(
				graph,
				config.VersionedInformerFactory.Core().V1().Nodes(),
				config.VersionedInformerFactory.Core().V1().Pods(),
				config.VersionedInformerFactory.Core().V1().PersistentVolumes(),
				config.VersionedInformerFactory.Storage().V1().VolumeAttachments(),
			)
			nodeAuthorizer := node.NewAuthorizer(graph, nodeidentifier.NewDefaultNodeIdentifier(), bootstrappolicy.NodeRules())
			authorizers = append(authorizers, nodeAuthorizer)
			ruleResolvers = append(ruleResolvers, nodeAuthorizer)

		case modes.ModeAlwaysAllow:
			alwaysAllowAuthorizer := authorizerfactory.NewAlwaysAllowAuthorizer()
			authorizers = append(authorizers, alwaysAllowAuthorizer)
			ruleResolvers = append(ruleResolvers, alwaysAllowAuthorizer)
		case modes.ModeAlwaysDeny:
			alwaysDenyAuthorizer := authorizerfactory.NewAlwaysDenyAuthorizer()
			authorizers = append(authorizers, alwaysDenyAuthorizer)
			ruleResolvers = append(ruleResolvers, alwaysDenyAuthorizer)
		case modes.ModeABAC:
			abacAuthorizer, err := abac.NewFromFile(config.PolicyFile)
			if err != nil {
				return nil, nil, err
			}
			authorizers = append(authorizers, abacAuthorizer)
			ruleResolvers = append(ruleResolvers, abacAuthorizer)
		case modes.ModeWebhook:
			if config.WebhookRetryBackoff == nil {
				return nil, nil, errors.New("retry backoff parameters for authorization webhook has not been specified")
			}
			clientConfig, err := webhookutil.LoadKubeconfig(config.WebhookConfigFile, config.CustomDial)
			if err != nil {
				return nil, nil, err
			}
			webhookAuthorizer, err := webhook.New(clientConfig,
				config.WebhookVersion,
				config.WebhookCacheAuthorizedTTL,
				config.WebhookCacheUnauthorizedTTL,
				*config.WebhookRetryBackoff,
			)
			if err != nil {
				return nil, nil, err
			}
			authorizers = append(authorizers, webhookAuthorizer)
			ruleResolvers = append(ruleResolvers, webhookAuthorizer)
		case modes.ModeRBAC:
			rbacAuthorizer := rbac.New(
				&rbac.RoleGetter{Lister: config.VersionedInformerFactory.Rbac().V1().Roles().Lister()},
				&rbac.RoleBindingLister{Lister: config.VersionedInformerFactory.Rbac().V1().RoleBindings().Lister()},
				&rbac.ClusterRoleGetter{Lister: config.VersionedInformerFactory.Rbac().V1().ClusterRoles().Lister()},
				&rbac.ClusterRoleBindingLister{Lister: config.VersionedInformerFactory.Rbac().V1().ClusterRoleBindings().Lister()},
			)
			authorizers = append(authorizers, rbacAuthorizer)
			ruleResolvers = append(ruleResolvers, rbacAuthorizer)
		default:
			return nil, nil, fmt.Errorf("unknown authorization mode %s specified", authorizationMode)
		}
	}

	return union.New(authorizers...), union.NewRuleResolvers(ruleResolvers...), nil
}

```


#### 总结
```go 
// authorizer实现了这个接口
type Authorizer interface {
	Authorize(ctx context.Context, a Attributes) (authorized Decision, reason string, err error)
}

genericConfig.Authorizer = groupedAuthorizer // groupedAuthorizer.Authorize
for _, authorizer  := range groupedAuthorizer {
    authorizer.Authorizer()
}
```

#### Authorizaer执行
