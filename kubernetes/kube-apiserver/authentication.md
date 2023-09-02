&emsp;Authentication options
```go 
// BuiltInAuthenticationOptions contains all build-in authentication options for API Server
type BuiltInAuthenticationOptions struct {
	APIAudiences    []string
	Anonymous       *AnonymousAuthenticationOptions
	BootstrapToken  *BootstrapTokenAuthenticationOptions
	ClientCert      *genericoptions.ClientCertAuthenticationOptions
	OIDC            *OIDCAuthenticationOptions
	RequestHeader   *genericoptions.RequestHeaderAuthenticationOptions
	ServiceAccounts *ServiceAccountAuthenticationOptions
	TokenFile       *TokenFileAuthenticationOptions
	WebHook         *WebHookAuthenticationOptions

	TokenSuccessCacheTTL time.Duration
	TokenFailureCacheTTL time.Duration
}


func NewBuiltInAuthenticationOptions() *BuiltInAuthenticationOptions {
	return &BuiltInAuthenticationOptions{
		TokenSuccessCacheTTL: 10 * time.Second,
		TokenFailureCacheTTL: 0 * time.Second,
	}
}

// WithAll set default value for every build-in authentication option
func (o *BuiltInAuthenticationOptions) WithAll() *BuiltInAuthenticationOptions {
	return o.
		WithAnonymous().
		WithBootstrapToken().
		WithClientCert().
		WithOIDC().
		WithRequestHeader().
		WithServiceAccounts().
		WithTokenFile().
		WithWebHook()
}
```

&emsp;修改
```go 
	completed.Authentication.ApplyAuthorization(completed.Authorization){
	if o.Anonymous.Allow && sets.NewString(authorization.Modes...).Has(authzmodes.ModeAlwaysAllow) {
		klog.Warningf("AnonymousAuth is not allowed with the AlwaysAllow authorizer. Resetting AnonymousAuth to false. You should use a different authorizer")
		o.Anonymous.Allow = false
	}
    }
```

// genericConfig = genericapiserver.NewConfig(legacyscheme.Codecs) // generciConfig = &Config{}

// genericConfig.AuthticationInfo = autenticationConfig.new() // AuthenticationRequest

#### 生成配置阶段
```go 
func (o *BuiltInAuthenticationOptions) ToAuthenticationConfig() (kubeauthenticator.Config, error) {
	ret := kubeauthenticator.Config{
		TokenSuccessCacheTTL: o.TokenSuccessCacheTTL,
		TokenFailureCacheTTL: o.TokenFailureCacheTTL,
	}
    // options的一些填充
	return ret, nil
}

// genericConfig = genericapiserver.NewConfig(legacyscheme.Codecs) // generciConfig = &Config{}

// genericConfig.AuthticationInfo = autentication.{....}
func (o *BuiltInAuthenticationOptions) ApplyTo(authInfo *genericapiserver.AuthenticationInfo, secureServing *genericapiserver.SecureServingInfo, egressSelector *egressselector.EgressSelector, openAPIConfig *openapicommon.Config, openAPIV3Config *openapicommon.Config, extclient kubernetes.Interface, versionedInformer informers.SharedInformerFactory) error {
	authenticatorConfig, err := o.ToAuthenticationConfig()
    // ... 相关Authentication 的配置
	authInfo.Authenticator, openAPIConfig.SecurityDefinitions, err = authenticatorConfig.New()

	return nil
}




// New returns an authenticator.Request or an error that supports the standard
// Kubernetes authentication mechanisms.
func (config Config) New() (authenticator.Request, *spec.SecurityDefinitions, error) {
	var authenticators []authenticator.Request
	var tokenAuthenticators []authenticator.Token
	securityDefinitions := spec.SecurityDefinitions{}

	if config.RequestHeaderConfig != nil {
		requestHeaderAuthenticator := headerrequest.NewDynamicVerifyOptionsSecure(/*some requestHeader args*/)
		authenticators = append(authenticators, authenticator.WrapAudienceAgnosticRequest(config.APIAudiences, requestHeaderAuthenticator))
	}

	// X509 methods
	if config.ClientCAContentProvider != nil {
		certAuth := x509.NewDynamic(config.ClientCAContentProvider.VerifyOptions, x509.CommonNameUserConversion)
		authenticators = append(authenticators, certAuth)
	}

	// Bearer token methods, local first, then remote
	if len(config.TokenAuthFile) > 0 {
		tokenAuth, err := newAuthenticatorFromTokenFile(config.TokenAuthFile)
		tokenAuthenticators = append(tokenAuthenticators, authenticator.WrapAudienceAgnosticToken(config.APIAudiences, tokenAuth))
	}

	if len(config.ServiceAccountKeyFiles) > 0 {
		serviceAccountAuth, err := newLegacyServiceAccountAuthenticator(config.ServiceAccountKeyFiles, config.ServiceAccountLookup, config.APIAudiences, config.ServiceAccountTokenGetter, config.SecretsWriter)
		tokenAuthenticators = append(tokenAuthenticators, serviceAccountAuth)
	}

	if len(config.ServiceAccountIssuers) > 0 {
		serviceAccountAuth, err := newServiceAccountAuthenticator(config.ServiceAccountIssuers, config.ServiceAccountKeyFiles, config.APIAudiences, config.ServiceAccountTokenGetter)
		tokenAuthenticators = append(tokenAuthenticators, serviceAccountAuth)
	}

	if config.BootstrapToken && config.BootstrapTokenAuthenticator != nil {
		tokenAuthenticators = append(tokenAuthenticators, authenticator.WrapAudienceAgnosticToken(config.APIAudiences, config.BootstrapTokenAuthenticator))
	}

	if len(config.OIDCIssuerURL) > 0 && len(config.OIDCClientID) > 0 {
		// TODO(enj): wire up the Notifier and ControllerRunner bits when OIDC supports CA reload
		var oidcCAContent oidc.CAContentProvider
		oidcAuth, err := newAuthenticatorFromOIDCIssuerURL(oidc.Options{/*some options*/ })
		tokenAuthenticators = append(tokenAuthenticators, authenticator.WrapAudienceAgnosticToken(config.APIAudiences, oidcAuth))
	}

	if len(config.WebhookTokenAuthnConfigFile) > 0 {
		webhookTokenAuth, err := newWebhookTokenAuthenticator(config)
		tokenAuthenticators = append(tokenAuthenticators, webhookTokenAuth)
	}


	if len(tokenAuthenticators) > 0 {
		// Union the token authenticators
		tokenAuth := tokenunion.New(tokenAuthenticators...)
		authenticators = append(authenticators, bearertoken.New(tokenAuth), websocket.NewProtocolAuthenticator(tokenAuth))
		securityDefinitions["BearerToken"] = &spec.SecurityScheme{ }
	}

	if len(authenticators) == 0 {
		if config.Anonymous {
			return anonymous.NewAuthenticator(), &securityDefinitions, nil
		}
		return nil, &securityDefinitions, nil
	}

	authenticator := union.New(authenticators...)

	authenticator = group.NewAuthenticatedGroupAdder(authenticator)

	if config.Anonymous {
		authenticator = union.NewFailOnError(authenticator, anonymous.NewAuthenticator())
	}

	return authenticator, &securityDefinitions, nil
}
```



&emsp;总结 
```go 
authenticationOptions  -> authenticationConfig -> authenticator ->(impl) -> []Authenticator.Request ([]Authentication.Request 同样实现了AuthenticationRequest)


genericConfig.Authenticator := groupAuthenticatorRequestImpl
```

#### Authenticatior执行
