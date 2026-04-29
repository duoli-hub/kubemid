# kubemid
## 部署步骤

### 1. 基础系统配置

配置基础网络、更新源等

### 2. 在每个节点安装依赖工具

推荐使用 ansible in docker 容器化方式运行，无需安装额外依赖

### 3. 准备 ssh 免密登录

配置从部署节点能够 ssh 免密登陆所有节点

##### 方法一：使用命令行工具手动配置

```bash
ssh-keygen
ssh-copy-id $IP		# $IP为所有节点地址包括自身，按照提示输入yes 和root密码
```

##### 方法二：使用脚本(`ssh-key-copy.sh`)

```bash
# 前提是已经正确配置hosts
cd tools && chmod +x ssh-key-copy.sh
./ssh-copy-id.sh $hosts		# $hosts为ansible中的hosts路径
```

### 4. 部署

##### 4.1 下载项目源码

下载工具脚本(`ezdown`)，例如：使用 `ezdown `版本 0.0.1

```bash
export release=0.0.1
wget https://github.com/duoli-hub/kubemid/releases/download/${release}/ezdown
chmod +x ./ezdown
```

下载 kubemid 代码、默认容器镜像（更多 ezdown 的参数，运行`./ezdown`查看）

```bash
./ezdown -D
```

上述脚本运行成功后，所有文件均已整理好放入目录`/etc/kubemid`

##### 4.2 创建配置

```bash
# 容器化运行 kubemid
./ezdown -S

# 设置命令别名
alias dk='docker exec -it kubemid'
source ~/.bashrc

# 创建配置
dk ezctl new
```

然后根据提示配置`/etc/kubemid/middleware/hosts` 和 `/etc/kubemid/middleware/config.yml`：根据节点规划修改 hosts 文件；其他配置项可以在config.yml 文件中修改

##### 4.3 开始安装	

```bash
dk ezctl setup nginx
dk ezctl setup redis
dk ezctl setup mysql
...

