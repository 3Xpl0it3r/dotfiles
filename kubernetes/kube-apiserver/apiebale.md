```go 

// ApplyTo override MergedResourceConfig with defaults and registry
func (s *APIEnablementOptions) ApplyTo(c *server.Config, defaultResourceConfig *serverstore.ResourceConfig, registry resourceconfig.GroupVersionRegistry) error {

	if s == nil {
		return nil
	}

	mergedResourceConfig, err := resourceconfig.MergeAPIResourceConfigs(defaultResourceConfig, s.RuntimeConfig, registry)
	c.MergedResourceConfig = mergedResourceConfig

	return err
}


// mergedResouces 
// default enable 36个 apiversion,  enable 
// disable 4 个apiversion
//  enable 4 个 resource
// merge的逻辑
// 1. 禁用apisever,  首先禁用apiversion, 然后查找resource，把符合resource设置disabkle
// 1,  enable apiserver, 首先启用apiversion, 然查找 resource 吧符合resource设置enable

```
