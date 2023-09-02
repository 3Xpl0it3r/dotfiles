&emsp;`Feature` Option定义如下
```go
type FeatureOptions struct {
	EnableProfiling           bool
	DebugSocketPath           string
	EnableContentionProfiling bool
}
```



## 生成Config阶段
&emsp;`Feature`最终是apply到apiserver配置里面
```go 
func (o *FeatureOptions) ApplyTo(c *server.Config) error {
	if o == nil {
		return nil
	}

	c.EnableProfiling = o.EnableProfiling
	c.DebugSocketPath = o.DebugSocketPath
	c.EnableContentionProfiling = o.EnableContentionProfiling

	return nil
}
```
