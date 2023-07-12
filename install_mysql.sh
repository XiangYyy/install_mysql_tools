#!/bin/bash
## Author：yanxiang
## Time:20220908
## 支持 MySQL5.7 mysql8.0 Centos Ubuntu
## 已测试:
### 操作系统:Centos7.9	Ubuntu20.4	Kylin V10 Rocky8
### mysql版本:8.0.30 5.7.39

## TODO
### 支持 mysql 8.0 主从相关配置
### 支持 mysql 同步、半同步配置

# set -eux
set -eu

# 无需配置，脚本使用全局变量
ARG_PORT=""
ARG_VERSION=""
PKG_NAME=""
PKG_PATH=""
OS_NAME=""
OS_VERSION=""
OS_CPU_TOTAL=""
OS_RAM_TOTAL=""
MAIN_VERSION_NU=""
SUB_VERSION_NU=""

SUPPORT_DEPLOY_TYPE=("local" "mgr" "semisync")

# 运行用户
RUN_USER="mysql"

USEARGS="
部署 MySQL

Usage:
  sudo sh install_mysql.sh -p [port] -v [version]

Flags:
  -p, --port        部署的 mysql 使用的端口
  -v, --version     要部署的 mysql 的版本
"

# 打印Error
function EchoError() {
	red_color='\E[1;31m'
	res='\E[0m'
	echo -e "${red_color}ERROR: ${1}${res}" >&2
}

# 打印INFO
function EchoInfo() {
	local green_color='\E[1;32m'
	local res='\E[0m'
	echo -e "${green_color}INFO: ${1}${res}"
}

# 校验运行脚本的用户
function CheckRunUser() {
	if [ $UID -ne 0 ]; then
		EchoError "Please use root or sudo run this script!!"
		exit 1
	fi
}

# 检查是否输入变量
function CheckEnterArgs() {
	if [[ $# -eq 0 ]]; then
		EchoError "Please run scripts with args"
		echo "$USEARGS"
		exit 1
	fi
}

function IsValueInList() {
	local value="$1"
	shift
	local list=("$@")

	for item in "${list[@]}"; do
		if [[ "$item" == "$value" ]]; then
			return 0 # 值在列表中
		fi
	done

	return 1 # 值不在列表中
}

# check port
function CheckPort() {
	local min_sys_tmp_port
	min_sys_tmp_port=$(awk '{print $1}' "/proc/sys/net/ipv4/ip_local_port_range")

	if ! [[ $ARG_PORT =~ ^[0-9]+$ ]] || [ "$ARG_PORT" -ge "$min_sys_tmp_port" ] ||
		[ "$ARG_PORT" -le "1024" ]; then
		EchoError "mysql port $ARG_PORT not allowed"
		exit 1
	fi

	if [ "$(ss -anlp | grep -wc "\:${ARG_PORT}")" -ne "0" ]; then
		EchoError "mysql port $ARG_PORT is listen"
		exit 1
	fi
	echo "mysql port check $ARG_PORT pass"

	if [ "$MAIN_VERSION_NU" = "8.0" ]; then
		if ! [[ $ADMIN_PORT =~ ^[0-9]+$ ]] || [ "$ADMIN_PORT" -ge "$min_sys_tmp_port" ] ||
			[ "$ADMIN_PORT" -le "1025" ]; then
			EchoError "admin port $ADMIN_PORT not allowed"
			exit 1
		fi

		if [ "$(ss -anlp | grep -wc "\:${ADMIN_PORT}")" -ne "0" ]; then
			EchoError "admin port $ADMIN_PORT is listen"
			exit 1
		fi
		echo "admin port check $ADMIN_PORT pass"
	fi

	if [ "$MAIN_VERSION_NU" = "8.0" ] && [ "$DEPLOY_TYPE" = "mgr" ]; then
		if ! [[ $MGR_PORT =~ ^[0-9]+$ ]] || [ "$MGR_PORT" -ge "$min_sys_tmp_port" ] ||
			[ "$MGR_PORT" -le "1025" ]; then
			EchoError "mgr port $MGR_PORT not allowed"
			exit 1
		fi

		if [ "$(ss -anlp | grep -wc "\:${MGR_PORT}")" -ne "0" ]; then
			EchoError "mgr port $MGR_PORT is listen"
			exit 1
		fi
		echo "mgr port check $MGR_PORT pass"
	fi
}

# 拼接包名
function InitAppendPkgName() {
	# local main_avg_nu
	MAIN_VERSION_NU=$(echo "$ARG_VERSION" | awk -v FS='.' -v OFS="." '{print $1,$2}')
	SUB_VERSION_NU=$(echo "$ARG_VERSION" | awk -F '.' '{print $3}')

	if [ "$MAIN_VERSION_NU" = "8.0" ]; then
		PKG_NAME="mysql-${ARG_VERSION}-linux-glibc2.12-x86_64.tar.xz"
	fi

	if [ "$MAIN_VERSION_NU" = "5.7" ]; then
		PKG_NAME="mysql-${ARG_VERSION}-linux-glibc2.12-x86_64.tar.gz"
	fi

	PKG_PATH="pkgs/$PKG_NAME"
}

# 获取操作系统基本信息
function InitGetOSMsg() {
	if [ -f "/etc/redhat-release" ] && [ "$(awk '{print $1}' /etc/redhat-release)" = "CentOS" ]; then
		OS_NAME="CentOS"
		OS_VERSION="$(awk -F 'release ' '{print $2}' /etc/redhat-release | awk '{print $1}' | awk -F '.' -v OFS='.' '{print $1,$2}')"
	elif [ -f "/etc/redhat-release" ] && [ "$(awk -v OFS='' '{print $1,$2}' /etc/redhat-release)" = "RedHat" ]; then
		OS_NAME="RedHat"
		OS_VERSION="$(awk -F 'release ' '{print $2}' /etc/redhat-release | awk '{print $1}')"
	elif [ -f "/etc/issue" ] && [ "$(awk '{print $1}' /etc/issue)" = "Ubuntu" ]; then
		OS_NAME="Ubuntu"
		OS_VERSION="$(awk '{print $2}' /etc/issue | head -n 1)"
	elif [ -f "/etc/kylin-release" ] && [ "$(awk '{print $1}' /etc/kylin-release)" = "Kylin" ]; then
		OS_NAME="Kylin"
		OS_VERSION="$(awk -F 'release ' '{print $2}' /etc/kylin-release | awk '{print $1}')"
	elif [ -f "/etc/redhat-release" ] && [ "$(awk '{print $1}' /etc/redhat-release)" = "Rocky" ]; then
		OS_NAME="Rocky"
		OS_VERSION="$(awk -F 'release ' '{print $2}' /etc/redhat-release | awk '{print $1}' | awk -F '.' -v OFS='.' '{print $1,$2}')"
	else
		EchoError "OS Not Support"
		exit 1
	fi

	OS_CPU_TOTAL=$(grep -c 'processor' /proc/cpuinfo)
	OS_RAM_TOTAL=$(free -g | grep Mem | awk '{print $2}')

	echo "OS_NAME=$OS_NAME"
	echo "OS_VERSION=$OS_VERSION"
	echo "OS_CPU_TOTAL=$OS_CPU_TOTAL"
	echo "OS_RAM_TOTAL=$OS_RAM_TOTAL"
}

# 安装系统依赖的基础包
function InstallSysPkgs() {
	if [ "$SKIP_SYS_PKG_INSTALL" -ne "0" ]; then
		EchoInfo "skip install sys pkgs"
		return 0
	fi

	if [ "$OS_NAME" = "CentOS" ] || [ "$OS_NAME" = "RedHat" ] || [ "$OS_NAME" = "Kylin" ] || [ "$OS_NAME" = "Rocky" ]; then
		EchoInfo "Install sys pkgs"
		if ! yum install perl perl-Data-Dumper libaio autoconf net-tools numactl tar -y; then
			EchoError "Install sys pkgs faild"
			exit 1
		fi
	fi

	if [ "$OS_NAME" = "Rocky" ]; then
		if ! yum install ncurses-compat-libs -y; then
			EchoError "Install sys pkgs faild"
			exit 1
		fi
	fi

	if [ "$OS_NAME" = "Ubuntu" ]; then
		EchoInfo "Install sys pkgs"
		if ! apt -y update || ! apt -y install libaio1 libncurses5; then
			EchoError "Install sys pkgs faild"
			exit 1
		fi
	fi
}

# 初始化相关
function Init() {

	if [ ! -f "./install_mysql.conf" ]; then
		EchoError 'config file "./install_mysql.conf" not found'
		exit 1
	fi

	InitAppendPkgName "$ARG_VERSION"
	EchoInfo "load install config"
	# load config
	# shellcheck source=/dev/null
	source "./install_mysql.conf"

	InitGetOSMsg
	InitAdminSetting
	InitMGRPORT
}

function InitAdminSetting() {
	if [ "$ADMIN_ADDRESS" = "" ]; then
		ADMIN_ADDRESS="127.0.0.1"
	fi

	if [ "$ADMIN_PORT" = "" ]; then
		ADMIN_PORT=$((ARG_PORT + 10000))
	fi
}

function InitMGRPORT() {
	if [ "$MGR_PORT" = "" ]; then
		MGR_PORT=$((ARG_PORT + 20000))
	fi
}

# check package version
function CheckPkgVersion() {
	# local main_avg_nu
	# main_avg_nu=$(echo "$ARG_VERSION" | awk -v FS='.' -v OFS="." '{print $1,$2}')
	if [ "$MAIN_VERSION_NU" != "8.0" ] && [ "$MAIN_VERSION_NU" != "5.7" ]; then
		EchoError "version $ARG_VERSION not support"
		exit 1
	fi

	if [ ! -f "${PKG_PATH}" ]; then
		EchoError "${PKG_PATH} not exists"
		exit 1
	fi
	echo "version check $ARG_VERSION pass"
}

# 校验文件是否为空
function CheckFileIsEmpty() {
	local check_path="$1"
	if [ -e "$check_path" ] &&
		[ "$(find "$check_path" -maxdepth 1 ! -name "$(basename "$check_path")" |
			wc -l)" -ne 0 ]; then
		EchoError "$check_path is not empty directories"
		exit 1
	fi
	echo "$check_path check pass"
}

# check install path
function CheckMySQLPath() {
	EchoInfo "check sys path"
	CheckFileIsEmpty "${MYSQL_BASE_PATH}"
	CheckFileIsEmpty "${MYSQL_DB_DATA_PATH}"
	CheckFileIsEmpty "${MYSQL_TMP_PATH}"
	CheckFileIsEmpty "${MYSQL_BINLOG_PATH}"
	CheckFileIsEmpty "${MYSQL_REDOLOG_PATH}"
	CheckFileIsEmpty "${MYSQL_RELAYLOG_PATH}"
}

# set centos/redhat sys settings
function SetCentOSSySSetting() {
	local tmp_date
	tmp_date=$(date +%Y%m%d%H%M%S)
	cp -rp "/etc/security/limits.d/" "./security_limits_${tmp_date}_bk"
	rm -rf /etc/security/limits.d/*
	cp "/etc/security/limits.conf" "./limits.conf.${tmp_date}.bk"
	cat >>/etc/security/limits.conf <<EOF
# add by install_mysql.sh
${RUN_USER}    soft    core       unlimited
${RUN_USER}    hard    core       unlimited
${RUN_USER}    soft    nproc       131072
${RUN_USER}    hard    nproc       131072
${RUN_USER}    soft    nofile       65536
${RUN_USER}    hard    nofile       65536
${RUN_USER}    soft    memlock       396826317
${RUN_USER}    hard    memlock       396826317
# end
EOF
}

# set ubuntu sys settings
function SetUbuntuSySSetting() {
	local tmp_date
	tmp_date=$(date +%Y%m%d%H%M%S)
	cp -rp "/etc/security/limits.d/" "./security_limits_${tmp_date}_bk"
	rm -rf /etc/security/limits.d/*
	cp "/etc/security/limits.conf" "./limits.conf.${tmp_date}.bk"
	cat >>/etc/security/limits.conf <<EOF
# add by install_mysql.sh
${RUN_USER}    soft    core       unlimited
${RUN_USER}    hard    core       unlimited
${RUN_USER}    soft    nproc       131072
${RUN_USER}    hard    nproc       131072
${RUN_USER}    soft    nofile       65536
${RUN_USER}    hard    nofile       65536
${RUN_USER}    soft    memlock       396826317
${RUN_USER}    hard    memlock       396826317
# end
EOF
}

# 创建 mysql 需要使用的目录
function SetSaveDir() {
	mkdir -p "$MYSQL_APP_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_APP_PATH"

	mkdir -p "$MYSQL_DATA_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_DATA_PATH"

	mkdir -p "$MYSQL_LOG_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_LOG_PATH"

	mkdir -p "$MYSQL_BASE_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_BASE_PATH"

	mkdir -p "$MYSQL_DB_DATA_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_DB_DATA_PATH"

	mkdir -p "$MYSQL_TMP_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_TMP_PATH"

	mkdir -p "$MYSQL_BINLOG_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_BINLOG_PATH"

	mkdir -p "$MYSQL_REDOLOG_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_REDOLOG_PATH"

	mkdir -p "$MYSQL_RELAYLOG_PATH"
	chown -R $RUN_USER.$RUN_USER "$MYSQL_RELAYLOG_PATH"

}

# 调整系统配置
function SetSysSetting() {
	InstallSysPkgs

	if [ "$OS_NAME" = "CentOS" ] || [ "$OS_NAME" = "RedHat" ] || [ "$OS_NAME" = "Kylin" ] || [ "$OS_NAME" = "Rocky" ]; then
		SetCentOSSySSetting
	fi
	if [ "$OS_NAME" = "Ubuntu" ]; then
		SetUbuntuSySSetting
	fi

	AddMySQLUser

}

# create mysql user
function AddMySQLUser() {
	if id "${RUN_USER}"; then
		EchoInfo "user $RUN_USER is exist,skip add user"
		return 0
	fi

	if [ "$OS_NAME" = "CentOS" ] || [ "$OS_NAME" = "RedHat" ] || [ "$OS_NAME" = "Kylin" ] || [ "$OS_NAME" = "Rocky" ]; then
		EchoInfo "add new user $RUN_USER"
		useradd -s /sbin/nologin -r -m $RUN_USER
	fi
	if [ "$OS_NAME" = "Ubuntu" ]; then
		EchoInfo "add new user $RUN_USER"
		useradd -s /sbin/nologin -r -m $RUN_USER
	fi
}

# 校验模板配置文件是否存在
function CheckTemplateConfigPath() {
	local template_config=""

	if [ "$MAIN_VERSION_NU" = "5.7" ]; then
		template_config="templates/my57.cnf"
	fi

	if [ "$MAIN_VERSION_NU" = "8.0" ]; then
		template_config="templates/my80.cnf"
	fi

	if [ ! -f "$template_config" ]; then
		EchoError "template config $template_config not found"
		exit 1
	fi
}

function CheckDeployType() {
	if ! IsValueInList "$DEPLOY_TYPE" "${SUPPORT_DEPLOY_TYPE[@]}"; then
		EchoError "DEPLOY TYPE $DEPLOY_TYPE not support,only support:${SUPPORT_DEPLOY_TYPE[*]}"
		exit 1
	fi

	if [ "$MAIN_VERSION_NU" = "5.7" ] && [ "$DEPLOY_TYPE" = "mgr" ]; then
		EchoError "this scripts on mysql 5.7 not support MGR"
		exit 1
	fi

	if [ "$MAIN_VERSION_NU" = "5.7" ] && [ "$DEPLOY_TYPE" = "semisync" ]; then
		EchoError "this scripts on mysql 5.7 not support Semi Synchronous Replication"
		exit 1
	fi

	if [ "$DEPLOY_TYPE" = "semisync" ]; then
		if [ "$SEMI_ROLE" != "leader" ] && [ "$SEMI_ROLE" != "flower" ]; then
			EchoError "Semi Synchronous Replication not support role: $SEMI_ROLE,only support: leader/flower"
			exit 1
		fi
	fi
}

# 预检
function PreCheck() {
	EchoInfo "start run precheck"
	CheckRunUser
	CheckPort
	CheckPkgVersion
	CheckMySQLPath
	CheckTemplateConfigPath
	CheckDeployType
}

# 开启 MGR 相关配置
function SETMySQLMGRConfig() {
	local my_config_path="$1"
	local group_replication_grou_address=""

	sed -i "s/#loose-plugin_load_add/loose-plugin_load_add/g" "$my_config_path"
	sed -i "s/#loose-group_replication_group_name/loose-group_replication_group_name/g" "$my_config_path"
	sed -i "s/#disabled_storage_engines/disabled_storage_engines/g" "$my_config_path"
	sed -i "s/#loose-group_replication_local_address/loose-group_replication_local_address/g" "$my_config_path"
	sed -i "s/#loose-group_replication_group_seeds/loose-group_replication_group_seeds/g" "$my_config_path"
	sed -i "s/#loose-group_replication_start_on_boot/loose-group_replication_start_on_boot/g" "$my_config_path"
	sed -i "s/#loose-group_replication_bootstrap_group/loose-group_replication_bootstrap_group/g" "$my_config_path"
	sed -i "s/#loose-group_replication_exit_state_action/loose-group_replication_exit_state_action/g" "$my_config_path"
	sed -i "s/#loose-group_replication_flow_control_mode/loose-group_replication_flow_control_mode/g" "$my_config_path"
	sed -i "s/#loose-group_replication_single_primary_mode/loose-group_replication_single_primary_mode/g" "$my_config_path"
	sed -i "s/#loose-group_replication_communication_max_message_size/loose-group_replication_communication_max_message_size/g" "$my_config_path"
	sed -i "s/#loose-group_replication_unreachable_majority_timeout/loose-group_replication_unreachable_majority_timeout/g" "$my_config_path"
	sed -i "s/#loose-group_replication_member_expel_timeout/loose-group_replication_member_expel_timeout/g" "$my_config_path"
	sed -i "s/#loose-group_replication_autorejoin_tries/loose-group_replication_autorejoin_tries/g" "$my_config_path"
	sed -i "s/#loose-group_replication_recovery_public_key_path/loose-group_replication_recovery_public_key_path/g" "$my_config_path"
	sed -i "s/#report_host/report_host/g" "$my_config_path"

	sed -i "s/{{ MGR_REPORT_HOST }}/$MGR_REPORT_HOST/g" "$my_config_path"
	sed -i "s/{{ MGR_PORT }}/$MGR_PORT/g" "$my_config_path"

	for ((i = 0; i < ${#GROUP_REPL_GROUP_IP[@]}; i++)); do
		if [ "${i}" -eq 0 ] && [[ ${group_replication_grou_address} = "" ]]; then
			group_replication_grou_address="${GROUP_REPL_GROUP_IP[i]}:${MGR_PORT}"
		else
			group_replication_grou_address="${group_replication_grou_address},${GROUP_REPL_GROUP_IP[i]}:${MGR_PORT}"
		fi
	done
	sed -i "s/{{ GROUP_REPLICATION_GROUP_ADDRESS }}/$group_replication_grou_address/g" "$my_config_path"

}

function SETMySQLSemySyncConfig() {
	local my_config_path="$1"

	sed -i "s/#loose-plugin_load/loose-plugin_load/g" "$my_config_path"

	# 更改 leader 角色的相关配置
	if [ "$SEMI_ROLE" = "leader" ]; then
		# 开启 主 semi
		sed -i "s/#loose-rpl_semi_sync_master_enabled/loose-rpl_semi_sync_master_enabled/g" "$my_config_path"
		# 设置 主 等待 ack 的时间
		sed -i "s/#loose-rpl_semi_sync_master_timeout/loose-rpl_semi_sync_master_timeout/g" "$my_config_path"
		# 设置 主 等待 ack 的个数
		sed -i "s/#loose-rpl_semi_sync_master_wait_for_slave_count/loose-rpl_semi_sync_master_wait_for_slave_count/g" "$my_config_path"
		# 设置主 sync 模式
		sed -i "s/#loose-rpl_semi_sync_master_wait_point/loose-rpl_semi_sync_master_wait_point/g" "$my_config_path"
	fi
	if [ "$SEMI_ROLE" = "leader" ]; then
		sed -i "s/#loose-rpl_semi_sync_slave_enabled/loose-rpl_semi_sync_slave_enabled/g" "$my_config_path"
		if [ "$SLAVE_READ_ONLY" -eq 1 ]; then
			sed -i "s/#read_only/read_only/g" "$my_config_path"
			sed -i "s/#super_read_only/super_read_only/g" "$my_config_path"
		fi
	fi

}

# 设置 MySQL 配置文件
function SetMySQLConfig() {
	local my_config_path
	my_config_path="$MYSQL_DATA_PATH/my_${ARG_PORT}.cnf"
	if [ "$MAIN_VERSION_NU" = "5.7" ]; then
		cp "templates/my57.cnf" "$my_config_path"

		if [ "$SUB_VERSION_NU" -ge "39" ]; then
			sed -i "s/myisam_repair_threads = 1/#myisam_repair_threads = 1/g" "$my_config_path"
		fi
	fi

	local skip_binary=""
	local log_slow_extra=""
	local binlog_checksum="CRC32"
	local innodb_buffer_pool_size="512m"

	if [ "$MAIN_VERSION_NU" = "8.0" ]; then
		cp "templates/my80.cnf" "$my_config_path"

		if [ "$SUB_VERSION_NU" -ge "19" ]; then
			skip_binary="loose-skip-binary-as-hex"
		fi

		if [ "$SUB_VERSION_NU" -ge "14" ]; then
			log_slow_extra="log_slow_extra = 1"
		fi

		if [ "$SUB_VERSION_NU" -le "22" ]; then
			binlog_checksum="NONE"
		fi

		if [ "$SUB_VERSION_NU" -ge "26" ]; then
			sed -i "s#slave#replica#g" "$my_config_path"
		fi

		if [ "$SUB_VERSION_NU" -lt "23" ]; then
			sed -i "s/replication_optimize_for_static_plugin_config/#replication_optimize_for_static_plugin_config/g" "$my_config_path"
			sed -i "s/replication_sender_observe_commit_only/#replication_sender_observe_commit_only/g" "$my_config_path"
		fi

		if [ "$SUB_VERSION_NU" -ge "23" ]; then
			sed -i "s/master_info_repository = TABLE/#master_info_repository = TABLE/g" "$my_config_path"
			sed -i "s/relay_log_info_repository = TABLE/#relay_log_info_repository = TABLE/g" "$my_config_path"
		fi

		if [ "$SUB_VERSION_NU" -ge "29" ]; then
			sed -i "s/myisam_repair_threads = 1/#myisam_repair_threads = 1/g" "$my_config_path"
		fi

		if [ "$INNODB_ONLY" -eq "1" ]; then
			sed -i "s/#disabled_storage_engines/disabled_storage_engines/g" "$my_config_path"
		fi

		sed -i "s#{{ ADMIN_ADDRESS }}#$ADMIN_ADDRESS#g" "$my_config_path"
		sed -i "s#{{ ADMIN_PORT }}#$ADMIN_PORT#g" "$my_config_path"

	fi

	# base settings
	sed -i "s#{{ RUN_USER }}#$RUN_USER#g" "$my_config_path"
	sed -i "s#{{ PORT }}#$ARG_PORT#g" "$my_config_path"
	sed -i "s#{{ MYSQL_BASE_PATH }}#$MYSQL_BASE_PATH#g" "$my_config_path"
	sed -i "s#{{ SKIP_BINARY }}#$skip_binary#g" "$my_config_path"

	if [ "$MYSQL_SERVER_ID" -le "0" ]; then
		MYSQL_SERVER_ID=$(date +%s)
	fi
	sed -i "s#{{ MYSQL_SERVER_ID }}#$MYSQL_SERVER_ID#g" "$my_config_path"
	sed -i "s#{{ MYSQL_SOCKET_PATH }}#$MYSQL_SOCKET_PATH#g" "$my_config_path"
	# sed -i "s#{{ INNODB_BUFFER_POOL_SIZE }}#1G#g" "$my_config_path"
	sed -i "s#{{ BINLOG_CHECKSUM }}#$binlog_checksum#g" "$my_config_path"

	if [ "$DEFAULT_NATIVE_PASSWORD" -ne "0" ]; then
		sed -i "s/#default_authentication_plugin/default_authentication_plugin/g" "$my_config_path"
		sed -i "s/#collation_server/collation_server/g" "$my_config_path"
	fi

	# data settings
	sed -i "s#{{ MYSQL_DB_DATA_PATH }}#$MYSQL_DB_DATA_PATH#g" "$my_config_path"
	sed -i "s#{{ MYSQL_TMP_PATH }}#$MYSQL_TMP_PATH#g" "$my_config_path"

	# log settings
	sed -i "s#{{ MYSQL_REDOLOG_PATH }}#$MYSQL_REDOLOG_PATH#g" "$my_config_path"
	sed -i "s#{{ MYSQL_LOG_PATH }}#$MYSQL_LOG_PATH#g" "$my_config_path"
	sed -i "s#{{ MYSQL_RELAYLOG_PATH }}#$MYSQL_RELAYLOG_PATH#g" "$my_config_path"
	sed -i "s#{{ MYSQL_BINLOG_PATH }}#$MYSQL_BINLOG_PATH#g" "$my_config_path"

	# others
	sed -i "s#{{ LOG_SLOW_EXTRA }}#$log_slow_extra#g" "$my_config_path"

	if [ "$OS_CPU_TOTAL" -ge "16" ]; then
		sed -i "s#{{ TBL_OPEN_CACHE_INSTANCES }}#16#g" "$my_config_path"
	else
		sed -i "s#{{ TBL_OPEN_CACHE_INSTANCES }}#8#g" "$my_config_path"
	fi
	sed -i "s#{{ SLAVE_PARALLEL_WORKERS }}#$OS_CPU_TOTAL#g" "$my_config_path"

	if [ "$OS_RAM_TOTAL" -ge "2" ]; then
		innodb_buffer_pool_size=$((OS_RAM_TOTAL / 2))G
	fi
	sed -i "s#{{ INNODB_BUFFER_POOL_SIZE }}#${innodb_buffer_pool_size}#" "$my_config_path"

	if [ "$DEPLOY_TYPE" = "mgr" ]; then
		SETMySQLMGRConfig "$my_config_path"
	fi
	if [ "$DEPLOY_TYPE" = "semisync" ]; then
		SETMySQLSemySyncConfig "$my_config_path"
	fi

}

# 初始化 mysql 数据
function InitMySQLDATA() {
	EchoInfo "init mysql data"
	# if [ "$MAIN_VERSION_NU" = "5.7" ]; then
	if ! "$MYSQL_BASE_PATH"/bin/mysqld \
		--defaults-file="$MYSQL_DATA_PATH/my_${ARG_PORT}.cnf" \
		--initialize-insecure --user="$RUN_USER" --basedir="$MYSQL_BASE_PATH" --datadir="${MYSQL_DB_DATA_PATH}"; then

		EchoError "init mysql data faild"
		exit 1
	fi
	EchoInfo "init mysql data success"
	# fi
}

# 设置启停脚本
function SetStartStopScripts() {
	cat >"${MYSQL_BASE_PATH}/start_${ARG_PORT}.sh" <<EOF
cd  ${MYSQL_BASE_PATH}
MY=\$(ps -ef |grep mysqld |grep -v grep|grep $ARG_PORT|wc -l)    
if [ \$MY -ge "2" ];then
    echo "MySQL port:$ARG_PORT is running!"
    exit
fi

./bin/mysqld_safe --defaults-file=$MYSQL_DATA_PATH/my_${ARG_PORT}.cnf &
sleep 3
MY=\$(ps -ef |grep mysqld |grep -v grep|grep $ARG_PORT|wc -l)
if [ \$MY -ge "2" ];then
    ps -ef |grep mysqld |grep -v grep|grep $ARG_PORT
    echo "MySQL port:$ARG_PORT Started [ok]!"
else
    echo "MySQL port:$ARG_PORT Started [false]"
fi
EOF
	cat >"${MYSQL_BASE_PATH}/stop_${ARG_PORT}.sh" <<EOF
cd  ${MYSQL_BASE_PATH}
MY=\$(ps -ef |grep mysqld |grep -v grep|grep $ARG_PORT|wc -l)
if [ \$MY -eq "0" ];then
    echo "MySQL port:$ARG_PORT is not runing!"
    exit
fi

./bin/mysqladmin -u root -p$MYSQL_PASS shutdown -S ${MYSQL_SOCKET_PATH}
sleep 2 
MY=\$(ps -ef |grep mysqld |grep -v grep|grep $ARG_PORT|wc -l)
if [ \$MY -eq "0" ];then
    echo "MySQL port:$ARG_PORT Stopped [ok]!"
else
    echo "MySQL port:$ARG_PORT  Stopped [false]!"
    echo "MySQL Info:"
    ps -ef |grep mysqld |grep -v grep|grep $ARG_PORT
fi
EOF

	chmod u+x "${MYSQL_BASE_PATH}/start_${ARG_PORT}.sh"
	chmod u+x "${MYSQL_BASE_PATH}/stop_${ARG_PORT}.sh"
}

# mysql 基础安全配置
function SetMySQLSecuritySetting() {
	EchoInfo "set mysql security setting"

	# if [ "$MAIN_VERSION_NU" = "5.7" ]; then
	echo "start mysql,sleepp 30s"
	"${MYSQL_BASE_PATH}"/bin/mysqld_safe --defaults-file="${MYSQL_DATA_PATH}/my_${ARG_PORT}.cnf" &
	sleep 30
	EchoInfo "set root password"
	"$MYSQL_BASE_PATH"/bin/mysqladmin -u root password "$MYSQL_PASS" -S "${MYSQL_SOCKET_PATH}"
	EchoInfo "delete sys user"
	echo "run delete from mysql.user where user='';delete from mysql.user where authentication_string='';flush privileges;"
	"$MYSQL_BASE_PATH"/bin/mysql -uroot -p"$MYSQL_PASS" -S "${MYSQL_SOCKET_PATH}" \
		-e "delete from mysql.user where user='';delete from mysql.user where authentication_string='';flush privileges;"
	# fi
}

# 安装 mysql
function InstallMySQL() {
	EchoInfo "unzip pkgs"
	local unzip_file_name
	unzip_file_name=$(echo $PKG_NAME | awk -F '.tar' '{print $1}')

	CheckFileIsEmpty "$MYSQL_APP_PATH/$unzip_file_name"

	mkdir -p "$MYSQL_APP_PATH"

	if [ "$MAIN_VERSION_NU" = "5.7" ]; then
		tar -zxvf ${PKG_PATH} -C "${MYSQL_APP_PATH}"
	fi

	if [ "$MAIN_VERSION_NU" = "8.0" ]; then
		tar -xvf ${PKG_PATH} -C "${MYSQL_APP_PATH}"
	fi

	chown $RUN_USER.$RUN_USER -R "$MYSQL_APP_PATH"
	# sudo -u ${RUN_USER} ln -sfn "${MYSQL_APP_PATH}/${unzip_file_name}" "$MYSQL_BASE_PATH"
	sudo -u $RUN_USER ln -sfn "${MYSQL_APP_PATH}/${unzip_file_name}" "$MYSQL_BASE_PATH"
}

# main
function main() {
	CheckEnterArgs "$@"

	GETOPT_ARGS=$(getopt -o "hp:v:" -al "help,port:,version:" -n "$0" -- "$@") || exit 1
	# [ $? -ne 0 ] && exit 1
	# echo "GETOPT_ARGS=$GETOPT_ARGS"
	eval set -- "$GETOPT_ARGS"

	while [ -n "${1-}" ]; do
		case $1 in
		-h | --help)
			echo "$USEARGS"
			exit 0
			;;
		-p | --port)
			ARG_PORT="$2"
			shift 2
			;;
		-v | --version)
			ARG_VERSION=$2
			shift 2
			;;
		--)
			shift
			;;
		*)
			EchoError "unrecognized option \'$1\'"
			exit 1
			;;
		esac
	done

	Init
	PreCheck
	SetSysSetting

	InstallMySQL
	SetSaveDir
	SetMySQLConfig
	InitMySQLDATA
	SetStartStopScripts
	SetMySQLSecuritySetting
	EchoInfo "mysql $ARG_VERSION run on $ARG_PORT install success!!"

}

main "$@"
