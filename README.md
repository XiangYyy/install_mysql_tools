# MySQL 部署脚本

## 兼容性
### 操作系统
+ 兼容 CentOS 7
+ 兼容 RedHat 7
+ 兼容 Ubuntu 20.04

### 兼容 mysql 版本
+ 兼容 MySQL5.7
  + 5.7.36+ 经过测试
+ 兼容 MySQL8.0
  + 8.0.28+ 经过测试

## 脚本配置说明(install_mysql.conf)
### 安装目录配置
+ MYSQL_APP_PATH：MySQL 安装目录
+ MYSQL_DATA_PATH：MySQL 数据文件存储位置(如无特殊需求，可使用默认配置)
+ MYSQL_LOG_PATH：MySQL 日志文件目录(如无特殊需求，可使用默认配置)
+ MYSQL_PASS：root@localhost 账号密码
+ ......

### 默认编码配置
+ DEFAULT_NATIVE_PASSWORD：配置为 1 后，配置文件会增加 default_authentication_plugin=mysql_native_password 以兼容 mysql5.7 默认加密格式，仅 mysql8.0 有效

### mgr 配置(仅 mysql8.0 有效)
+ MGR_ENABLE：是否开启 mgr
+ MGR_REPORT_HOST：部署 mysql 的节点 ip
+ GROUP_REPL_GROUP_IP：MGR 集群所有节点 ip
+ MGR_PORT：MGR 集群通信端口
  + 端口需与 mysql 端口和 mysql admin 端口不同
  + 如不配置，默认为 mysql 端口 + 2w
+ 具体配置参考：https://blog.xiangy.cloud/post/mysql8.0-install-mgr/


### 其他配置
+ SKIP_SYS_PKG_INSTALL：为 1 则运行脚本时，脚本不使用 apt/yum 安装 mysql 依赖的包
+ MYSQL_SERVER_ID：mysql 的 server_id，如果为 0 ，则会根据系统时间自动生成
+ ADMIN_ADDRESS：admin port 监听的 ip，仅 mysql8.0 有效
+ ADMIN_PORT：admin port 监控的 端口，如不配置则默认为 mysql port + 1w，仅 mysql8.0 有效


## 使用
+ 将 mysql 二进制安装包放在脚本的 pkgs 目录下。下载地址：
  + https://dev.mysql.com/downloads/mysql/
  + https://downloads.mysql.com/archives/community/
+ 更改脚本配置(install_mysql.conf)
+ 运行脚本
  + 运行脚本时通过 -v 指定安装的 mysql 版本，通过 -p 指定 mysql 监控的端口

```bash
sudo bash install_mysql.sh -v 8.0.28 -p 3306
```
+ 脚本运行成功后会自动开启 mysql，后续启停操作可通过 mysql 目录下(如：/data/mysql3306/mysql8.0.28) start_3306.sh/stop_3306.sh 两脚本控制