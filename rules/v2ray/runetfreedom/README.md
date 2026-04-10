# v2ray-rules

自用的 v2rayN / Xray 路由规则，适用于按域名、GeoSite、GeoIP 进行分流。

## 特性

- 支持 GFW 域名走代理
- 支持 Google、GitHub 等常用站点单独分流
- 支持广告拦截
- 支持腾讯下载直连
- 支持局域网 IP / 局域网域名直连
- 支持扩展 GeoIP 分流
- 适配 v2rayN 自定义路由规则导入

## 依赖说明

本规则使用了第三方扩展 Geo 文件，请先将 v2rayN 的 **Geo 文件来源** 设置为：

```text
https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/{0}.dat
```

否则以下扩展 `geoip` 规则可能无法正常生效：

- `geoip:cloudflare`
- `geoip:cloudfront`
- `geoip:facebook`
- `geoip:fastly`
- `geoip:google`
- `geoip:netflix`
- `geoip:telegram`
- `geoip:twitter`
- `geoip:ddos-guard`
- `geoip:yandex`

## 使用前准备

在 v2rayN 中完成以下设置：

1. 打开 **设置**
2. 右边 **v2rayN设置**
3. 找到 **Geo 文件来源（可选）**
4. 填入：

```text
https://github.com/runetfreedom/russia-v2ray-rules-dat/releases/latest/download/{0}.dat
```

4. 更新一次 **Geo 文件**
5. 重启 v2rayN 核心
6. 再导入本仓库中的规则文件

## 导入方法

### 方法一：从剪贴板导入
适合直接复制规则内容使用。

### 方法二：从文件导入
将规则保存为 `.json` 文件后，在 v2rayN 中导入。

### 方法三：从订阅 URL 导入
将规则文件上传到 GitHub，并使用原始直链导入。

例如：

```text
https://raw.githubusercontent.com/ldxw/cdn/master/rules/v2ray/runetfreedom/v2ray-rules.json
```

## 规则说明

当前规则主要包含以下内容：

- **代理远程 DNS**
  - `cloudflare-dns.com`
  - `dns.google`

- **代理 GFW 域名**
  - `geosite:gfw`
  - `geosite:greatfire`

- **腾讯下载直连**
  - `scdown.qq.com`
  - `qbwup.imtt.qq.com`
  - `update.browser.qq.com`

- **GitHub 代理**
  - `github.com`
  - `githubassets.com`
  - `githubusercontent.com`

- **Google 代理**
  - `geosite:google`

- **广告拦截**
  - `googleads.g.doubleclick.net`
  - `adservice.google.com`
  - `geosite:category-ads-all`
  - `geosite:win-spy`

- **局域网直连**
  - `geoip:private`
  - `geosite:private`

- **常用直连域名**
  - Bitwarden
  - Let's Encrypt
  - Adobe
  - Microsoft
  - Apple
  - 中国大陆常用域名

- **扩展 GeoIP 代理**
  - Cloudflare
  - CloudFront
  - Facebook
  - Fastly
  - Google
  - Netflix
  - Telegram
  - Twitter
  - DDOS-GUARD
  - Yandex

## 注意事项

1. 如果没有先更新第三方 Geo 文件，扩展 `GeoIP` 规则不会正常生效。
2. 更新 v2rayN 程序后，Geo 文件有可能被覆盖，建议重新检查 Geo 文件来源并再次更新。
3. 如果规则导入后可用但访问异常，优先检查：
   - DNS 设置
   - Geo 文件是否已更新
   - 路由规则顺序是否正确
   - 当前核心是否已重启

## 推荐规则集别名

导入到 v2rayN 时，规则集别名建议填写：

```text
gfw黑名单（需第三方GeoIP）
```

## 适用环境

- v2rayN
- Xray
- 使用 `geosite` / `geoip` 进行分流的客户端环境

## 免责声明

本项目仅供学习、研究与个人规则管理使用，请根据自己的网络环境自行调整。
