&emsp;`Audit` option
```go 
// AuditWebhookOptions control the webhook configuration for audit events.
type AuditWebhookOptions struct {
	ConfigFile     string
	InitialBackoff time.Duration

	BatchOptions    AuditBatchOptions
	TruncateOptions AuditTruncateOptions

	// API group version used for serializing audit events.
	GroupVersionString string
}

func NewAuditOptions() *AuditOptions {
	return &AuditOptions{
		WebhookOptions: AuditWebhookOptions{
			InitialBackoff: pluginwebhook.DefaultInitialBackoffDelay,
			BatchOptions: AuditBatchOptions{
				Mode:        ModeBatch,
				BatchConfig: defaultWebhookBatchConfig(),
			},
			TruncateOptions:    NewAuditTruncateOptions(),
			GroupVersionString: "audit.k8s.io/v1",
		},
		LogOptions: AuditLogOptions{
			Format: pluginlog.FormatJson,
			BatchOptions: AuditBatchOptions{
				Mode:        ModeBlocking,
				BatchConfig: defaultLogBatchConfig(),
			},
			TruncateOptions:    NewAuditTruncateOptions(),
			GroupVersionString: "audit.k8s.io/v1",
		},
	}
}
```

### 创建Audit
```go 
func (o *AuditOptions) ApplyTo( c *server.Config,) error {
	// 1. Build policy evaluator
	evaluator, err := o.newPolicyRuleEvaluator()

	// 2. Build log backend
	var logBackend audit.Backend
	w, err := o.LogOptions.getWriter()

	// 3. Build webhook backend
	var webhookBackend audit.Backend
	webhookBackend, err = o.WebhookOptions.newUntruncatedBackend(egressDialer)

	groupVersion, err := schema.ParseGroupVersion(o.WebhookOptions.GroupVersionString)

	// 4. Apply dynamic options.
	var dynamicBackend audit.Backend
	if webhookBackend != nil {
		// if only webhook is enabled wrap it in the truncate options
		dynamicBackend = o.WebhookOptions.TruncateOptions.wrapBackend(webhookBackend, groupVersion)
	}

	// 5. Set the policy rule evaluator
	c.AuditPolicyRuleEvaluator = evaluator

	// 6. Join the log backend with the webhooks
	c.AuditBackend = appendBackend(logBackend, dynamicBackend)

	if c.AuditBackend != nil {
		klog.V(2).Infof("Using audit backend: %s", c.AuditBackend)
	}
	return nil
}

```

#### Aduit执行
