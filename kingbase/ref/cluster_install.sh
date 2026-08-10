#!/bin/bash

shell_folder=$(dirname $(readlink -f "$0"))

# normal configuration
on_bmj=0
ha_running_mode=""
all_ip=()
witness_ip=""
production_ip=()
local_disaster_recovery_ip=()
remote_disaster_recovery_ip=()
install_dir=""
zip_package=""
license_path="${shell_folder}"
trusted_servers=""
running_under_failure_trusted_servers=""
virtual_ip=""
net_device=()
net_device_ip=()
execute_user="kingbase"
super_user="root"

install_conf=""

# db configuration
db_user="system"
db_password=""
db_port="54321"
db_mode="oracle"
db_auth=""
db_case_sensitive=""
db_checksums=""
archive_mode="on"

data_directory=""
waldir=""

# cluster configuration
deploy_by_sshd=1
use_scmd=1

reconnect_attempts="10"
reconnect_interval="6"
connection_timeout="10"
recovery=""
auto_cluster_recovery_level="1"
ssh_port=""
use_check_disk=""
scmd_port=""

ipaddr_path=""
arping_path=""
ping_path=""

# the parameters do not need to be configured
soft_top_dir="/opt/Kingbase/ES/V8"
soft_dir="${soft_top_dir}/Server"
repmgrd_pid_file=""
kbha_pid_file=""
log_file=""
kbha_log_file=""

initdb_options=""
witness_initdb_options=""
basebackup_options=""

conninfo=""
sys_bindir=""
sys_logdir=""
cron_name=""
primary_host=""

#check connect between nodes
binary_local=""
binary_remote=""

is_ipv6=""

connection_timeout=10
usersetip=$*
synchronous=""
sync_in_same_location=""
cron_file="/etc/cron.d/KINGBASECRON"

function check_prm()
{
    name=$1
    prm=$2
    if [ "$prm"x == ""x ]
    then
        echo "[CONFIG_CHECK] param [$name] is not set in config file \"${install_conf}\" or in myself shell script"
        exit 1
    fi
}
function check_prm_is_integer()
{
    name=$1
    prm=$2
    local is_integer=`echo "$prm"|tr -d [0-9]`
    if [ "$is_integer"x != ""x ]
    then
        echo "[CONFIG_CHECK] param [$name] is not integer in config file \"${install_conf}\" or in myself shell script"
        exit 1
    fi
}
function load_config()
{
    #install.conf path，current path/install.conf
    [ "${install_conf}"x = ""x ] && install_conf="${shell_folder}/install.conf"

    #if install.conf exists, read the file
    load_conf_value_under_header $install_conf install

    [ "${on_bmj}"x = ""x ] && on_bmj=0
    [ $on_bmj -eq 0 ] && install_dir=${install_dir}/kingbase
    [ $on_bmj -eq 1 ] && install_dir=${soft_dir}
    [ $on_bmj -eq 1 ] && license_path=(${soft_top_dir}/license.dat)
    [ "${deploy_by_sshd}"x = ""x ] && deploy_by_sshd=1
    [ "${use_scmd}"x = ""x ] && use_scmd=1
	[ "${connection_timeout}"x = ""x ] && connection_timeout=10

    if [ "${usersetip}"x != ""x ]
    then
        all_ip=(${usersetip})
    fi

    if [ "$function_name"x = "install"x ]
    then
        if [ "${all_ip}"x = ""x ]
        then
            if [ "${production_ip}"x = ""x ]
            then
                # if all_ip and production_ip both are NULL, print error message.
                echo "[CONFIG_CHECK] param [all_ip] and [production_ip] are not set in config file \"${install_conf}\" or in myself shell script"
                return 1
            elif [ "${local_disaster_recovery_ip}"x = ""x ]
            then
                echo "[CONFIG_CHECK] param [local_disaster_recovery_ip] is not set in config file \"${install_conf}\" or in myself shell script"
                return 1
            fi

            if [ ${#remote_disaster_recovery_ip[@]} -gt 1 ]
            then
                echo "[CONFIG_CHECK] param [remote_disaster_recovery_ip] could only set one IP"
                return 1
            fi
            ha_running_mode="TPTC"
            all_ip=("${production_ip[@]}" "${local_disaster_recovery_ip[@]}" "${remote_disaster_recovery_ip[@]}")
        else
            if [ "${production_ip}"x != ""x ]
            then
                echo "[CONFIG_CHECK] param [production_ip] could not be set when [all_ip] is not NULL"
                return 1
            elif [ "${local_disaster_recovery_ip}"x != ""x ]
            then
                echo "[CONFIG_CHECK] param [local_disaster_recovery_ip] could not be set when [all_ip] is not NULL"
                return 1
            elif [ "${remote_disaster_recovery_ip}"x != ""x ]
            then
                echo "[CONFIG_CHECK] param [remote_disaster_recovery_ip] could not be set when [all_ip] is not NULL"
                return 1
            fi
            ha_running_mode="DG"
        fi
    fi
    # check all_ip for IPv4 or IPv6
    for ip in ${all_ip[@]}
    do
        tmp_is_ipv6=`echo "$ip" | grep -o ":" | wc -l`
        if [ "${is_ipv6}"x = ""x ]
        then
            if [ "${tmp_is_ipv6}"x = "0"x ]
            then
                is_ipv6=0
            else
                is_ipv6=1
            fi
        elif [ "${tmp_is_ipv6}"x != "0"x -a ${is_ipv6} -eq 0 ] || [ "${tmp_is_ipv6}"x = "0"x -a ${is_ipv6} -ne 0 ]
        then
            if [ "${ha_running_mode}"x = "DG"x ]
            then
                echo "[CONFIG_CHECK] the ip in [all_ip] can not have both IPv4 and IPv6"
            else
                echo "[CONFIG_CHECK] the ip in [production_ip/local_disaster_recovery_ip/remote_disaster_recovery_ip] can not have both IPv4 and IPv6"
            fi
            exit 1
        fi
    done
    echo "[CONFIG_CHECK] will deploy the cluster of ${ha_running_mode}"

    if [ "${install_dir}"x = ""x ]
    then
        echo "[CONFIG_CHECK] param [install_dir] is not set in config file \"${install_conf}\" or in myself shell script"
        return 1
    fi

    if [ "$function_name"x == "install"x ]
    then
        check_deploy_by_sshd
        if [ "${trusted_servers}"x = ""x ]
        then
            echo "[CONFIG_CHECK] param [trusted_servers] is not set in config file \"${install_conf}\" or in myself shell script"
            return 1
        else
            tmp_is_ipv6=`echo "${trusted_servers}" | grep -o ":" | wc -l`
            if [ "${tmp_is_ipv6}"x != "0"x -a ${is_ipv6} -eq 0 ]
            then
                echo "[CONFIG_CHECK] the [trusted_servers] must match the type of [all_ip]"
                exit 1
            elif [ "${tmp_is_ipv6}"x = "0"x -a ${is_ipv6} -ne 0 ]
            then
                echo "[CONFIG_CHECK] the [trusted_servers] must match the type of [all_ip]"
                exit 1
            fi
        fi

        if [ "${witness_ip}"x != ""x ]
        then
            if [ "$ha_running_mode"x = "TPTC"x ]
            then
                echo "[CONFIG_CHECK] the [witness_ip] must be NULL when deploy the cluster of ${ha_running_mode}"
                exit 1
            fi

            tmp_is_ipv6=`echo "${witness_ip}" | grep -o ":" | wc -l`
            if [ "${tmp_is_ipv6}"x != "0"x -a ${is_ipv6} -eq 0 ]
            then
                echo "[CONFIG_CHECK] the [witness_ip] must match the type of [all_ip]"
                exit 1
            elif [ "${tmp_is_ipv6}"x = "0"x -a ${is_ipv6} -ne 0 ]
            then
                echo "[CONFIG_CHECK] the [witness_ip] must match the type of [all_ip]"
                exit 1
            fi
        fi

        if [ "${virtual_ip}"x != ""x ]
        then
            if [ ${is_ipv6} -ne 0 ]
            then
                echo "[CONFIG_CHECK] when [all_ip] is IPv6, the [virtual_ip] is not supported now."
                exit 1
            fi
            tmp_is_ipv6=`echo "${virtual_ip}" | grep -o ":" | wc -l`
            if [ "${tmp_is_ipv6}"x != "0"x -a ${is_ipv6} -eq 0 ]
            then
                echo "[CONFIG_CHECK] the [virtual_ip] must be IPv4 (equal with [all_ip])"
                exit 1
            elif [ "${tmp_is_ipv6}"x = "0"x -a ${is_ipv6} -ne 0 ]
            then
                echo "[CONFIG_CHECK] the [virtual_ip] must be IPv6 (equal with [all_ip])"
                exit 1
            fi
        fi
    fi

    if [ "${db_password}"x = ""x ]; then
        db_password=`echo MTIzNDU2NzhhYgo= | base64 -d`
    fi

    if [ "${es_password}"x = ""x ]; then
        es_password=`echo MTIzNDU2Cg== | base64 -d`
    fi

	if [ -n "${tcp_keepalives_idle}" ]; then
		if [[ ! ${tcp_keepalives_idle} =~ ^[0-9]+$ ]]; then
			echo "[CONFIG_CHECK] the [tcp_keepalives_idle] must be digit"
			exit 1
		fi
	fi

	if [ -n "${tcp_keepalives_interval}" ]; then
		if [[ ! ${tcp_keepalives_interval} =~ ^[0-9]+$ ]]; then
			echo "[CONFIG_CHECK] the [tcp_keepalives_interval] must be digit"
			exit 1
		fi
	fi

	if [ -n "${tcp_keepalives_count}" ]; then
		if [[ ! ${tcp_keepalives_count} =~ ^[0-9]+$ ]]; then
			echo "[CONFIG_CHECK] the [tcp_keepalives_count] must be digit"
			exit 1
		fi
	fi

	if [ -n "${tcp_user_timeout}" ]; then
		if [[ ! ${tcp_user_timeout} =~ ^[0-9]+$ ]]; then
			echo "[CONFIG_CHECK] the [tcp_user_timeout] must be digit"
			exit 1
		fi
	fi

    local time_units_hint=("us" "ms" "s" "min" "h" "d")
    if [ -n "${wal_sender_timeout}" ]; then
        local tmp_wal_sender_timeout=$(echo ${wal_sender_timeout} | sed -e 's/[0-9]*//')
        local tmp_val=$(echo ${wal_sender_timeout} | sed -e 's/\(^[0-9]*\).*/\1/')
        if [ -z "${tmp_val}" ]; then
            echo "Parameter wal_sender_timeout's invalid value: " ${wal_sender_timeout}
            exit 1
        fi

        # unit must be one of time_units_hint
        if [ -n "${tmp_wal_sender_timeout}" ]; then
            local has_found=false
            for item in ${time_units_hint[@]}; do
                if [ "${item}" = "${tmp_wal_sender_timeout}" ]; then
                    has_found=true
                    break
                fi
            done

            if [ "${has_found}"x != "true"x ]; then
                echo "Parameter wal_sender_timeout's invalid value: " ${wal_sender_timeout}
                echo "Valid units for wal_sender_timeout are \"us\", \"ms\", \"s\", \"min\", \"h\", and \"d\"."
                exit 1
            fi
        fi
    fi

    if [ -n "${wal_receiver_timeout}" ]; then
        local tmp_wal_receive_timeout=$(echo ${wal_receiver_timeout} | sed -e 's/[0-9]*//')
        local tmp_val=$(echo ${wal_receiver_timeout} | sed -e 's/\(^[0-9]*\).*/\1/')
        if [ -z "${tmp_val}" ]; then
            echo "Parameter wal_receiver_timeout's invalid value: " ${wal_receiver_timeout}
            exit 1
        fi

        # unit must be one of time_units_hint
        if [ -n "${tmp_wal_receive_timeout}" ]; then
            local has_found=false
            for item in ${time_units_hint[@]}; do
                if [ "${item}" = "${tmp_wal_receive_timeout}" ]; then
                    has_found=true
                    break
                fi
            done

            if [ "${has_found}"x != "true"x ]; then
                echo "Parameter wal_receiver_timeout's invalid value: " ${wal_receiver_timeout}
                echo "Valid units for wal_receiver_timeout are \"us\", \"ms\", \"s\", \"min\", \"h\", and \"d\"."
                exit 1
            fi
        fi
    fi

    return 0
}

function pre_exe()
{
    load_config
    [ $? -ne 0 ] && exit 1

    check_and_get_user

    [ "${db_port}"x = ""x ] && db_port="54321"
    [ "${db_auth}"x = ""x ] && db_auth="scram-sha-256"
    [ "${db_case_sensitive}"x = ""x ] && db_case_sensitive="yes"
    [ "${db_checksums}"x = ""x ] && db_checksums="yes"
    [ "${archive_mode}"x = ""x ] && archive_mode="on"
    [ "${reconnect_attempts}"x = ""x ] && reconnect_attempts="10"
    [ "${reconnect_interval}"x = ""x ] && reconnect_interval="6"
    [ "${recovery}"x = ""x ] && recovery="standby"
    [ "${auto_cluster_recovery_level}"x = ""x ] && auto_cluster_recovery_level="1"
    [ "${sys_bindir}"x = ""x ] && sys_bindir="${install_dir}/bin"
    [ "${sys_logdir}"x = ""x ] && sys_logdir="${install_dir}/log"
    [ "${ssh_port}"x = ""x ] && ssh_port="22"
    [ "${use_check_disk}"x = ""x ] && use_check_disk="off"
    [ "${scmd_port}"x = ""x ] && scmd_port="8890"
    [ "${sync_in_same_location}"x = ""x ] && sync_in_same_location="0"
    [ "${failover_need_server_alive}"x = ""x ] && failover_need_server_alive="off"
    [ "${running_under_failure_trusted_servers}"x = ""x ] && running_under_failure_trusted_servers="on"

    if [ "$function_name"x = "expand"x ]
    then
        load_conf_value_under_header ${install_conf} expand
        check_prm primary_ip "$primary_ip"
        check_prm expand_ip "$expand_ip"
        check_prm node_id "$node_id"
        check_prm_is_integer node_id "$node_id"
        check_prm expand_type "$expand_type"
        [ "${on_bmj}"x = ""x ] && on_bmj=0
        if [ `stat -c %U $shell_folder/cluster_install.sh`x == "root"x ]
        then
            echo "cluster_install.sh file owner is root, set on_bmj=1"
            on_bmj=1
        else
            on_bmj=0
        fi
        [ $on_bmj -eq 0 ] && install_dir=${install_dir}/kingbase
        [ $on_bmj -eq 1 ] && install_dir=${soft_dir}
        [ "$ssh_port"x = ""x ] && ssh_port="22"
        [ "$scmd_port"x = ""x ] && scmd_port="8890"
        [ "${deploy_by_sshd}"x = ""x ] && deploy_by_sshd=1
        sys_bindir="${install_dir}/bin"
        repmgr_conf=${install_dir}/etc/repmgr.conf
        node_tools_conf=${install_dir}/etc/all_nodes_tools.conf
        scmd_conf=/etc/.kes/securecmd_config
        check_deploy_by_sshd
        check_net "$expand_ip"
        check_net "$primary_ip"
        super_user=root
        execute_user=`stat -c %U ${shell_folder}/cluster_install.sh`
        check_primary_ip "$primary_ip"
        load_config_from_cluster
        if [ $on_bmj -eq 1 ]
        then
            license_path=(${soft_top_dir}/license.dat)
        else
            check_prm license_file "$license_file"
            if [ ${#license_file[@]} -ne 1 ]
            then
                echo "[CONFIG_CHECK] \"license_file:${license_file}\" count must equal to 1"
                exit 1
            fi
        fi

        if [ "${virtual_ip}"x != ""x ]
        then
            check_prm net_device "$net_device"
            check_prm net_device_ip "$net_device_ip"
            if [ ${#net_device_ip[@]} -ne 1 ]
            then
                echo "[CONFIG_CHECK] \"net_device_ip:${net_device_ip}\" count must equal to 1"
                exit 1
            fi
            if [ ${#net_device[@]} -ne 1 ]
            then
                echo "[CONFIG_CHECK] \"net_device:${net_device}\" count must equal to 1"
                exit 1
            fi
            [ "${ipaddr_path}"x = ""x ] && ipaddr_path="/sbin"
            [ "${arping_path}"x = ""x ] && arping_path="${sys_bindir}"
        fi
        should_exit=1
        for type in {0,1}
        do
            [ "$expand_type"x == "$type"x ] && should_exit=0
        done
        if [ $should_exit -eq 1 ]
        then
            echo "[CONFIG_CHECK] param [expand_type] set error in config file \"${install_conf}\", it just could be set 0 or 1! "
            exit 1
        fi
    elif [ "$function_name"x = "shrink"x ]
    then
        load_conf_value_under_header ${install_conf} shrink
        check_prm primary_ip "$primary_ip"
        check_prm shrink_ip "$shrink_ip"
        check_prm shrink_type "$shrink_type"
        check_prm node_id "$node_id"
        check_prm_is_integer node_id "$node_id"
        super_user=root
        execute_user=`stat -c %U ${shell_folder}/cluster_install.sh`
        [ "${on_bmj}"x = ""x ] && on_bmj=0
        if [ `stat -c %U $shell_folder/cluster_install.sh`x == "root"x ]
        then
            echo "cluster_install.sh file owner is root, set on_bmj=1"
            on_bmj=1
        else
            on_bmj=0
        fi
        [ $on_bmj -eq 0 ] && install_dir=${install_dir}/kingbase
        [ $on_bmj -eq 1 ] && install_dir=${soft_dir}
        [ "$ssh_port"x = ""x ] && ssh_port="22"
        [ "$scmd_port"x = ""x ] && scmd_port="8890"
        [ "${deploy_by_sshd}"x = ""x ] && deploy_by_sshd=1
        sys_bindir="${install_dir}/bin"
        repmgr_conf=${install_dir}/etc/repmgr.conf
        node_tools_conf=${install_dir}/etc/all_nodes_tools.conf
        scmd_conf=/etc/.kes/securecmd_config
        check_deploy_by_sshd
        check_net "$shrink_ip"
        check_net "$primary_ip"
        check_primary_ip "$primary_ip"
        load_config_from_cluster
        should_exit=1
        for type in {0,1}
        do
            [ "$shrink_type"x == "$type"x ] && should_exit=0
        done
        if [ $should_exit -eq 1 ]
        then
            echo "[CONFIG_CHECK] param [shrink_type] set error in config file \"${install_conf}\",it just could be set 0 or 1"
            exit 1
        fi
    fi

    # write the scmd_options into repmgr.conf
    if [ $use_scmd -eq 1 ]
    then
        binary_remote="${sys_bindir}/sys_securecmd"
        port_remote="${scmd_port}"
        scmd_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${scmd_port}"
    else
        binary_remote="ssh"
        port_remote="${ssh_port}"
        scmd_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${ssh_port}"
    fi

    if [ -n "${tcp_keepalives_interval}" ]; then
        scmd_options="${scmd_options} -o ServerAliveInterval=${tcp_keepalives_interval}"
    fi

    if [ -n "${tcp_keepalives_count}" ]; then
	    scmd_options="${scmd_options} -o ServerAliveCountMax=${tcp_keepalives_count}"
    fi

    # used by execute_command
    if [ "$deploy_by_sshd"x == "1"x ]
    then
        binary_local="ssh"
        port_local="${ssh_port}"
        command_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${ssh_port}"
    else
        binary_local="${sys_bindir}/sys_securecmd"
        port_local="${scmd_port}"
        command_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${scmd_port}"
    fi

    if [ -n "${tcp_keepalives_interval}" ]; then
        command_options="${command_options} -o ServerAliveInterval=${tcp_keepalives_interval}"
    fi

    if [ -n "${tcp_keepalives_count}" ]; then
	    command_options="${command_options} -o ServerAliveCountMax=${tcp_keepalives_count}"
    fi

    if [ "${data_directory}"x = ""x ]
    then
        [ ${on_bmj} -eq 0 ] && data_directory="${install_dir}/data"
        [ ${on_bmj} -eq 1 ] && data_directory="${soft_top_dir}/data"
    fi

    [ "${repmgrd_pid_file}"x = ""x ] && repmgrd_pid_file="${install_dir}/etc/hamgrd.pid"
    [ "${kbha_pid_file}"x = ""x ] && kbha_pid_file="${install_dir}/etc/kbha.pid"
    [ "${log_file}"x = ""x ] && log_file="${sys_logdir}/hamgr.log"
    [ "${kbha_log_file}"x = ""x ] && kbha_log_file="${sys_logdir}/kbha.log"
    [ "${conninfo}"x = ""x ] && conninfo="user=esrep dbname=esrep port=${db_port}"

    if [ "$function_name"x == "install"x ]
    then
        if [ $on_bmj -eq 0 ]
        then
            if [ ${data_directory} != "${install_dir}/data" ]
            then
                if [ ! -d `dirname ${data_directory}` ]
                then
                    echo "[ERROR] the path: `dirname ${data_directory}` does not exist."
                    exit 1
                else
                    [ ! -w `dirname ${data_directory}` -a ! -r `dirname ${data_directory}` ] && echo "[ERROR] you have no permission for `dirname ${data_directory}`" && exit 1
                fi
            fi
        else
            if [ ${data_directory} != "${soft_top_dir}/data" ]
            then
                if [ ! -d `dirname ${data_directory}` ]
                then
                    echo "[ERROR] the path: `dirname ${data_directory}` does not exist."
                    exit 1
                else
                    [ ! -w `dirname ${data_directory}` -a ! -r `dirname ${data_directory}` ] && echo "[ERROR] you have no permission for `dirname ${data_directory}`" && exit 1
                fi
            fi
        fi
    fi
    if [ "$function_name"x != "shrink"x ]
    then
        if [ $deploy_by_sshd -eq 1 ]
        then
            name_zip=`echo $zip_package |grep -e "zip$" |wc -l`
            name_tar=`echo $zip_package |grep -e "tar$" |wc -l`
            name_gz=`echo $zip_package |grep -e "tar.gz$" |wc -l`
            if [ "${zip_package}"x = ""x ]
            then
                echo "[CONFIG_CHECK] param [zip_package] is not set in config file \"${install_conf}\" or in myself shell script"
                return 1
            else
                if [ $name_zip -eq 1 -o $name_tar -eq 1 -o $name_gz -eq 1 ]
                then
                    echo "[CONFIG_CHECK] file format is correct ... OK"
                else
                    echo "[ERROR] only \".zip\" \".tar\" and \".tar.gz\" could be supported."
                    exit 1
                fi
            fi
        fi
        if [ "${waldir}"x != ""x ]
        then
            if [[ $waldir =~ $data_directory ]]
            then
                echo "[ERROR] the [waldir] is included in [$data_directory]"
                exit 1
            fi
        fi
        if [ "${use_check_disk}"x = "on"x -o "${use_check_disk}"x = "1"x -o "${use_check_disk}"x = "yes"x -o "${use_check_disk}"x = "true"x ]
        then
            use_check_disk="on"
        elif [ "${use_check_disk}"x = "off"x -o "${use_check_disk}"x = "0"x -o "${use_check_disk}"x = "no"x -o "${use_check_disk}"x = "false"x ]
        then
            use_check_disk="off"
        else
            echo "[CONFIG_CHECK] the value of \"use_check_disk\" only could be 'on' or 'off'"
            exit 1
        fi
        if [ "${running_under_failure_trusted_servers}"x = "on"x -o "${running_under_failure_trusted_servers}"x = "1"x -o "${running_under_failure_trusted_servers}"x = "yes"x -o "${running_under_failure_trusted_servers}"x = "true"x ]
        then
            running_under_failure_trusted_servers="on"
        elif [ "${running_under_failure_trusted_servers}"x = "off"x -o "${running_under_failure_trusted_servers}"x = "0"x -o "${running_under_failure_trusted_servers}"x = "no"x -o "${running_under_failure_trusted_servers}"x = "false"x ]
        then
            running_under_failure_trusted_servers="off"
        else
            echo "[CONFIG_CHECK] the value of \"running_under_failure_trusted_servers\" only could be 'on' or 'off'"
            exit 1
        fi
        if [ "${db_password}"x = ""x ]
        then
            echo "[CONFIG_CHECK] the value of \"db_password\" can not be NULL, please set it install.conf or in myself shell script"
            exit 1
        fi
        if [ "$expand_type"x == "1"x  -o "$function_name"x == "install"x ]
        then
            if [ "${db_mode}"x != "oracle"x -a "${db_mode}"x != "pg"x -a "${db_mode}"x != "mysql"x ]
            then
                echo "[CONFIG_CHECK] the value of \"db_mode\" can only set as \"oracle\" or \"pg\" or \"mysql\""
                exit 1
            fi
            if [ "${db_case_sensitive}"x != "yes"x -a "${db_case_sensitive}"x != "no"x ]
            then
                echo "[CONFIG_CHECK] the value of \"db_case_sensitive\" can only set as \"yes\" or \"no\""
                exit 1
            fi
            # db_case_sensitive must be yes in PG mode
            if [ "${db_case_sensitive}"x != "yes"x -a "${db_mode}"x = "pg"x ]
            then
                echo "[CONFIG_CHECK] the value of \"db_case_sensitive\" can only set as \"yes\" when \"db_mode='pg'\""
                exit 1
            fi
            # db_case_sensitive must be no in mysql mode
            if [ "${db_case_sensitive}"x != "no"x -a "${db_mode}"x = "mysql"x ]
            then
                echo "[WARNING] the value of \"db_case_sensitive\" can only set as \"no\" when \"db_mode='mysql'\""
                echo "[CONFIG_CHECK] set db_case_sensitive=\"no\""
                db_case_sensitive="no"
            fi
            if [ "${db_mode}"x = "mysql"x ] && [[ $other_db_init_options = *--scenario-tuning* ]]
            then
                echo "[CONFIG_CHECK] \"--scenario-tuning\" cannot be set when \"db_mode='mysql'\""
                exit 1
            fi
            if [ "${db_checksums}"x != "yes"x -a "${db_checksums}"x != "no"x ]
            then
                echo "[CONFIG_CHECK] the value of \"db_checksums\" can only set as \"yes\" or \"no\""
                exit 1
            fi

            if [ "${archive_mode}"x != "off"x -a "${archive_mode}"x != "on"x -a "${archive_mode}"x != "always"x ]
            then
                echo "[CONFIG_CHECK] the value of \"archive_mode\" can only set as \"off\" or \"on\" or \"always\""
                exit 1
            fi

            check_and_set_initdb_options
        fi
    fi
    if [ "${db_user}"x = ""x ]
    then
        echo "[CONFIG_CHECK] the value of \"db_user\" can not be NULL, please set it install.conf or in myself shell script"
        exit 1
    fi

    if [ "${db_auth}"x != "scram-sha-256"x -a "${db_auth}"x != "md5"x ]
    then
        echo "[CONFIG_CHECK] the value of \"db_auth\" can only set as \"scram-sha-256\" or \"md5\""
        exit 1
    fi

    [ "${ping_path}"x = ""x ] && ping_path="/bin"
    if [ ${is_ipv6} -eq 0 ]
    then
        if [ ! -f "${ping_path}/ping" ]
        then
            echo "[CONFIG_CHECK] the dir \"${ping_path}\" has no execute file \"ping\", please set [ping_path] in install.conf or in myself shell script"
            exit 1
        fi
    else
        if [ ! -f "${ping_path}/ping6" ]
        then
            echo "[CONFIG_CHECK] the dir \"${ping_path}\" has no execute file \"ping6\", please set [ping_path] in install.conf or in myself shell script"
            exit 1
        fi
    fi

    if [ "$function_name"x == "install"x ]
    then
        if [ "${virtual_ip}"x != ""x ]
        then
            if [ "${ha_running_mode}"x = "TPTC"x ]
            then
                echo "[CONFIG_CHECK] \"virtual_ip\" could not used when deployed cluster of ${ha_running_mode}."
                exit 1
            fi

            vip_ip=${virtual_ip%/*}
            [ "${ipaddr_path}"x = ""x ] && ipaddr_path="/sbin"
            [ "${arping_path}"x = ""x ] && arping_path="${sys_bindir}"

            if [ ! -f "${ipaddr_path}/ip" ]
            then
                echo "[CONFIG_CHECK] the dir \"${ipaddr_path}\" has no execute file \"ip\", please set [ipaddr_path] in install.conf or in myself shell script"
                exit 1
            fi
            if [ "${net_device}"x = ""x ]
            then
                echo "[CONFIG_CHECK] \"net_device\" is NULL, please set it in install.conf or in myself shell script"
                exit 1
            fi

            if [ ${#net_device_ip[@]} -ne ${#all_ip[@]} ]
            then
                echo "[CONFIG_CHECK] \"net_device_ip\" count must equal to \"all_ip\""
                exit 1
            fi

            local i=0
            for ip in ${net_device_ip[@]}
            do
                tmp_is_ipv6=`echo "${ip}" | grep -o ":" | wc -l`
                if [ "${tmp_is_ipv6}"x != "0"x -a ${is_ipv6} -eq 0 ]
                then
                    echo "[CONFIG_CHECK] the ip in [net_device_ip] must be IPv4 (equal with [virtual_ip])"
                    exit 1
                elif [ "${tmp_is_ipv6}"x = "0"x -a ${is_ipv6} -ne 0 ]
                then
                    echo "[CONFIG_CHECK] the ip in [net_device_ip] must be IPv6 (equal with [virtual_ip])"
                    exit 1
                fi

                let i++
            done

            local is_vip_exist=""
            echo "[CONFIG_CHECK] check if the virtual ip \"${vip_ip}\" already exist ..."
            if [ "${is_ipv6}"x = "0"x ]
            then
                is_vip_exist=`${ping_path}/ping ${vip_ip} -c 3 -w 3 | grep received | awk '{print $4}'`
            else
                is_vip_exist=`${ping_path}/ping6 ${vip_ip} -c 3 -w 3 | grep received | awk '{print $4}'`
            fi
            if [ $? -ne 0 ] || [ $is_vip_exist -gt 0 ]
            then
                echo "[CONFIG_CHECK] `date +'%Y-%m-%d %H:%M:%S'` The virtual ip [${virtual_ip}] has already exists, exit."
                exit 1
            fi
            echo "[CONFIG_CHECK] there is no \"${vip_ip}\" on any host, OK"

            net_num=${#net_device[@]}
            if [ $net_num -eq ${#all_ip[@]} -o $net_num -eq 1 ]
            then
                echo "[CONFIG_CHECK] the number of net_device matches the length of all_ip or the number of net_device is 1 ... OK"
            else
                echo "[CONFIG_CHECK] the number of net_device is inconsistent with the number of all_ip or the number of net_device is not 1, please check your install.conf file, exit."
                exit 1
            fi
        fi

        if [ "${witness_ip}"x != ""x ]
        then
            all_ip[${#all_ip[*]}]=${witness_ip}
            echo "[CONFIG_CHECK] all_ip with witness: ${all_ip[@]}"
        fi

        if [ $deploy_by_sshd -eq 1 ]
        then
            license_num=${#license_file[@]}
            if [ $license_num -eq ${#all_ip[@]} -o $license_num -eq 1 ]
            then
                echo "[CONFIG_CHECK] the number of license_num matches the length of all_ip or the number of license_num is 1 ... OK"
            else
                echo "[CONFIG_CHECK] the number of license_num is inconsistent with the number of all_ip or the number of license_num is not 1, please check your install.conf file, exit."
                exit 1
            fi
        fi
    fi
    if [ "$function_name"x == "expand"x -o "$function_name"x == "install"x ]
    then
        if test ! -f ${zip_package}
        then
            if [ $on_bmj -eq 1 ]
            then
                echo "[CONFIG_CHECK] BMJ does not require to set param [zip_package] .... ok"
            elif [ $deploy_by_sshd -eq 0 ]
            then
                echo "[CONFIG_CHECK] when deploy_by_sshd=0, does not require to set param [zip_package] .... ok"
            else
                echo "[CONFIG_CHECK] check the zip file \"${zip_package}\" is not exist"
                exit 1
            fi
        fi

        if [ "${ha_running_mode}"x = "TPTC"x ]
        then
            if [ "${auto_cluster_recovery_level}"x != "0"x ]
            then
                echo "[CONFIG_CHECK] set the auto_cluster_recovery_level to 0 when deployed cluster of ${ha_running_mode}."
                auto_cluster_recovery_level="0"
            fi
            [ "${synchronous}"x = ""x ] && synchronous="all"

            if [ "${sync_in_same_location}"x != "0"x -a "${sync_in_same_location}"x != "1"x ]
            then
                echo "[CONFIG_CHECK] the value of \"sync_in_same_location\" could only be '0' or '1'"
                exit 1
            fi

            if [ "${failover_need_server_alive}"x != "off"x -a "${failover_need_server_alive}"x != "none"x -a "${failover_need_server_alive}"x != "any"x -a "${failover_need_server_alive}"x != "all"x ]
            then
                echo "[CONFIG_CHECK] failover_need_server_alive=${failover_need_server_alive} is not valid, could only be one of {'off', 'none', 'any', 'all'}"
                exit 1
            fi
        else
            [ "${synchronous}"x = ""x ] && synchronous="quorum"
        fi

        if [ "${synchronous}"x != "quorum"x -a "${synchronous}"x != "sync"x -a "${synchronous}"x != "all"x -a "${synchronous}"x != "async"x ]
        then
            echo "[CONFIG_CHECK] synchronous=${synchronous} is not valid, could only be one of {'async', 'sync', 'quorum', 'all'}"
            exit 1
        fi
    fi
}

function check_and_get_user()
{
    [ $on_bmj -eq 1 ] && execute_user="root"
    [ "${execute_user}"x = ""x ] && execute_user="kingbase"
    [ "${super_user}"x = ""x ] && super_user="root"
}

function test_ssh()
{
    local host=$1

    execute_command ${super_user} $host "/bin/true 2>/dev/null"
    if [ $? -eq 0 ]
    then
        return 0
    fi

    execute_command ${super_user} $host "/usr/bin/true 2>/dev/null"
    if [ $? -eq 0 ]
    then
        return 0
    fi

    return 1
}

function test_connect()
{
    local ip1="$1"
    local ip2="$2"

    [ "$ip1"x = ""x -a "$ip2"x = ""x ] && return 0

    # binary_local and binary_remote is set in pre_exe()
    if [ "$ip2"x = ""x ]
    then
        $binary_local ${command_options} -l ${super_user} -T $ip1 "/bin/true 2>/dev/null"
        [ $? -eq 0 ] && return 0
        $binary_local ${command_options} -l ${super_user} -T $ip1 "/usr/bin/true 2>/dev/null"
        [ $? -eq 0 ] && return 0
    else
        $binary_local ${command_options} -l ${super_user} -T $ip1 "$binary_remote ${scmd_options} -l ${super_user} -T $ip2 \"/bin/true 2>/dev/null\""
        [ $? -eq 0 ] && return 0
        $binary_local ${command_options} -l ${super_user} -T $ip1 "$binary_remote ${scmd_options} -l ${super_user} -T $ip2 \"/usr/bin/true 2>/dev/null\""
        [ $? -eq 0 ] && return 0
    fi
    return 1
}

function execute_command()
{
    local user=$1
    local host=$2
    local command=$3

    if [ $deploy_by_sshd -eq 1 ]
    then
        ssh ${command_options} -l ${user} -T $host "${command}"
        [ $? -ne 0 ] && return 1
    else
        ${sys_bindir}/sys_securecmd ${command_options} -l ${user} -T $host "${command}"
        [ $? -ne 0 ] && return 1
    fi

    return 0
}
function test_encode()
{
    local encode_name=$1
    local encode_value=$2
    for ip in ${all_ip[@]}
    do
        test_ssh $ip
        if [ $? -ne 0 ]
        then
            echo "[CONFIG_CHECK] cannot connect to $ip ..."
            exit 1
        fi
        encode_exits=`execute_command ${super_user} $ip "locale -a |grep -aiE "$encode_value" |wc -l"`
        if [ $encode_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking $encode_name:$encode_value exists on $ip ....fail"
            exit 1
        else
            echo "[CONFIG_CHECK] checking $encode_name:$encode_value exists on $ip ....OK"
        fi
    done
}
function set_encoding_initdb_options()
{
    [ "$db_encoding"x == ""x -a "$db_collate"x == ""x -a "$db_ctype"x == ""x ] && return 0
    if [ "$db_encoding"x == ""x ]
    then
       [ "$db_collate"x != ""x -o "$db_ctype"x != ""x ] && echo "[CONFIG_CHECK] db_encoding:($db_encoding) must be set value,when db_ctype:($db_ctype) or db_collate:($db_collate) is not null" && exit 1
    fi
    local encoding_is_posix=`echo $db_encoding |tr 'A-Z' 'a-z'`
    local collate_is_posix=`echo $db_collate |tr 'A-Z' 'a-z'`
    local ctype_is_posix=`echo $db_ctype |tr 'A-Z' 'a-z'`

    if [ "$db_encoding"x != ""x ]
    then
        test_encode "db_encoding" $db_encoding
        local utf_8_exits=`echo "$db_encoding" | grep -aEi "utf-8" |wc -l`

        echo "[CONFIG_CHECK] checking db_encoding:$db_encoding ..."
        if [ $utf_8_exits -gt 0 ]
        then
            echo "[CONFIG_CHECK] checking db_encoding:$db_encoding,utf-8 should be set as utf8   ...fail"
            exit 1
        fi
        if [ "$db_encoding"x == "C"x -o  "$db_encoding"x == "c"x -o "$encoding_is_posix"x == "posix"x ]
        then
           echo "[CONFIG_CHECK] checking db_encoding:$db_encoding,can not be set to C(posix)   ...fail！"
           exit 1
        fi
        echo "[CONFIG_CHECK] checking db_encoding:$db_encoding,utf-8 should be set as utf8  ...OK"

    fi
    if [ "$db_collate"x != ""x -a "$db_collate"x != "C"x -a "$db_collate"x != "c"x -a "$collate_is_posix"x != "posix"x ]
    then
        test_encode "db_collate" $db_collate
        local dot_exits=`echo "$db_collate" | grep "\." |wc -l`
        local utf_8_exits=`echo "$db_collate" | grep "utf-8" |wc -l`
        local regex_exits=`echo "$db_collate" |  grep -aE "[_a-z]*.[A-Za-z0-9]*"|wc -l`
        echo "[CONFIG_CHECK] checking db_collate:$db_collate ..."
        if [ $utf_8_exits -gt 0 ]
        then
            echo "[CONFIG_CHECK] checking db_collate:$db_collate  utf-8 should be set as utf8...fail!"
            exit 1
        fi
        if [ $dot_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking db_collate:$db_collate  dot_exits:$dot_exits...fail!"
            exit 1
        fi
        if [ $regex_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking db_collate:$db_collate  regex_exits:$regex_exits...fail!"
            exit 1
        fi
        local db_collate_prefix=`echo "$db_collate"|awk -F "." '{ printf $1 }'`
        local prefix_exits=`locale -a |grep  "$db_collate_prefix" |wc -l`
        if [ $prefix_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking db_collate:$db_collate prefix_exits:$prefix_exits  ...fail!"
            exit 1
        fi
        echo "[CONFIG_CHECK] checking db_collate:$db_collate ...OK"
    fi
    if [ "$db_ctype"x != ""x -a "$db_ctype"x != "C"x -a "$db_ctype"x != "c"x -a "$ctype_is_posix"x != "posix"x ]
    then
        test_encode "db_ctype" $db_ctype
        local dot_exits=`echo "$db_ctype" | grep "\." |wc -l`
        local utf_8_exits=`echo "$db_ctype" | grep "utf-8" |wc -l`
        local regex_exits=`echo "$db_ctype" | grep -aE "[_a-z]*.[A-Za-z0-9]*"|wc -l`

        echo "[CONFIG_CHECK] checking db_ctype:$db_ctype ..."
        if [ $utf_8_exits -gt 0 ]
        then
            echo "[CONFIG_CHECK] checking db_ctype:$db_ctype utf-8 should be set as utf8 ... fail"
            exit 1
        fi
        if [ $dot_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking db_ctype:$db_ctype dot_exits:$dot_exits ... fail"
            exit 1
        fi
        if [ $regex_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking db_ctype:$db_collate  regex_exits:$regex_exits...fail!"
            exit 1
        fi

        local db_ctype_prefix=`echo "$db_ctype"|awk -F "." '{ printf $1 }'`
        local prefix_exits=`locale -a |grep  "$db_ctype_prefix" |wc -l`
        if [ $prefix_exits -eq 0 ]
        then
            echo "[CONFIG_CHECK] checking db_ctype:$db_ctype prefix_exits:$prefix_exits  ...fail!"
            exit 1
        fi

        echo "[CONFIG_CHECK] checking db_ctype:$db_ctype ...OK"
    fi
    if [ "$db_encoding"x == ""x -o "$db_encoding"x == "C"x -o "$db_encoding"x == "c"x -o "$encoding_is_posix"x == "posix"x ]
    then
        local db_encoding_lower=""
    else
        local db_encoding_lower=`echo "$db_encoding"|tr 'A-Z' 'a-z'`
    fi

    if [ "$db_collate"x == ""x ]
    then
        local db_collate_default=`locale |grep "LC_COLLATE"|awk -F "=" '{ print $2 }' |tr -d '"'`
        local db_collate_suffix_lower=`echo "$db_collate_default"|awk -F "." '{ printf $2 }' |tr 'A-Z' 'a-z'`
    elif [ "$db_collate"x == "C"x -o "$db_collate"x == "c"x -o "$collate_is_posix"x == "posix"x ]
    then
        local db_collate_suffix_lower=""
    else
        local db_collate_suffix_lower=`echo "$db_collate"|awk -F "." '{ printf $2 }' |tr 'A-Z' 'a-z'`
    fi

    if [ "$db_ctype"x == ""x ]
    then
        local db_ctype_default=`locale |grep "LC_CTYPE"|awk -F "=" '{ print $2 }' |tr -d '"'`
        local db_ctype_suffix_lower=`echo "$db_ctype_default"|awk -F "." '{ printf $2 }' |tr 'A-Z' 'a-z'`
    elif [ "$db_ctype"x == "C"x -o "$db_ctype"x == "c"x  -o "$ctype_is_posix"x == "posix"x ]
    then
        local db_ctype_suffix_lower=""
    else
        local db_ctype_suffix_lower=`echo "$db_ctype"|awk -F "." '{ printf $2 }' |tr 'A-Z' 'a-z'`
    fi

    local array=("$db_encoding_lower" "$db_ctype_suffix_lower" "$db_collate_suffix_lower")
    local first_value=""
    for value in ${array[@]};do
        [ "$first_value"x == ""x -a "$value"x != ""x  ] && first_value=$value && continue
        [ "$value"x == ""x ] && continue
        echo "[CONFIG_CHECK] comparing $first_value  with $value   ..."
        if [ "$value"x != "$first_value"x ]
        then
            echo "[CONFIG_CHECK] $first_value is not same with $value ... check fail"
            exit 1
        fi
        echo "[CONFIG_CHECK] comparing $first_value  with $value   ...OK"
    done

    [ "${db_encoding}"x != ""x ] && initdb_options="${initdb_options} -E=${db_encoding}"
    [ "${db_collate}"x != ""x ] && initdb_options="${initdb_options} --lc-collat=${db_collate}"
    [ "${db_ctype}"x != ""x ] && initdb_options="${initdb_options} --lc-ctype=${db_ctype}"

}

function check_and_set_initdb_options()
{
    # initdb options for priamry/witness nodes.
    [ "${db_case_sensitive}"x = "no"x ] && initdb_options="${initdb_options} --enable-ci"
    [ "${db_checksums}"x = "yes"x ] && initdb_options="${initdb_options} --data-checksums"

    # initdb options of encoding
    set_encoding_initdb_options
    [ "${other_db_init_options}"x != ""x ] && initdb_options="${initdb_options} ${other_db_init_options}"
    witness_initdb_options="${initdb_options}"

    #initdb options only for primary node; basebackup options for standby node.
    if [ "${waldir}"x != ""x ]
    then
        initdb_options="${initdb_options} --waldir=${waldir}"
        basebackup_options="--waldir=${waldir}"
    fi
}

function check_and_change_system()
{
    local ip=$1
    echo "$(date +"%Y-%m-%d %T") [INFO] start to check system parameters on $ip ..."
    if [ $on_bmj -eq 0 ]
    then
        GSSAPIAuthentication=`execute_command ${super_user} $ip "cat /etc/ssh/sshd_config 2>/dev/null|grep ^GSSAPIAuthentication | tail -n 1"`
        GSSAPIAuthentication_values=`echo $GSSAPIAuthentication |awk '{print $2}'`
        GSSAPIAuthentication_v=`echo ${GSSAPIAuthentication_values} | tr '[A-Z]' '[a-z]'`
        if [ "$GSSAPIAuthentication_v"x = "no"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [GSSAPIAuthentication] $GSSAPIAuthentication_v on $ip"
        elif [ "$GSSAPIAuthentication_v"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [GSSAPIAuthentication] is null on $ip"
        else
            echo "$(date +"%Y-%m-%d %T") [WARNING] [GSSAPIAuthentication] $GSSAPIAuthentication_v (should be: no) on $ip"
        fi

        UseDNS=`execute_command ${super_user} $ip "cat /etc/ssh/sshd_config 2>/dev/null|grep ^UseDNS | tail -n 1"`
        UseDNS_values=`echo $UseDNS |awk '{print $2}'`
        UseDNS_v=`echo ${UseDNS_values} | tr '[A-Z]' '[a-z]'`
        if [ "$UseDNS_v"x = "no"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [UseDNS] $UseDNS_v  on $ip"
        elif [ "$UseDNS_v"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [UseDNS] is null on $ip"
        else
            echo "$(date +"%Y-%m-%d %T") [WARNING] [UseDNS] $UseDNS_v (should be: no) on $ip"
        fi

        count=0
        while [ $count -lt 3 ]
        do
            flag=0
            UsePAM=`execute_command ${super_user} $ip "cat /etc/ssh/sshd_config 2>/dev/null|grep ^UsePAM | tail -n 1"`
            UsePAM_values=`echo $UsePAM |awk '{print $2}'`
            UsePAM_v=`echo ${UsePAM_values} | tr '[A-Z]' '[a-z]'`
            if [ "$UsePAM_v"x = "yes"x ]
            then
                echo "$(date +"%Y-%m-%d %T") [INFO] [UsePAM] $UsePAM_v  on $ip"
            elif [ "$UsePAM_v"x = ""x ]
            then
                echo "$(date +"%Y-%m-%d %T") [ERROR] [UsePAM] is null on $ip"
                flag=1
            else
                echo "$(date +"%Y-%m-%d %T") [ERROR] [UsePAM] $UsePAM_v (should be: yes) on $ip"
                flag=1
            fi
            if [ $flag -eq 1 ]
            then
                echo "$(date +"%Y-%m-%d %T") [INFO] the value of [UsePAM] is wrong, now will change it on $ip ..."
                execute_command ${super_user} $ip "test -f /etc/ssh/sshd_config"
                if [ $? -eq 0 ];then
                    echo "$(date +"%Y-%m-%d %T") [INFO] change UsePAM on $ip ..."
                    execute_command ${super_user} $ip "sed -i \"s/^UsePAM[ ]*/#UsePAM/g\" /etc/ssh/sshd_config"
                    execute_command ${super_user} $ip "echo \"\" >> /etc/ssh/sshd_config"
                    execute_command ${super_user} $ip "echo \"UsePAM yes\" >> /etc/ssh/sshd_config"
                    echo "$(date +"%Y-%m-%d %T") [INFO] change UsePAM on $ip ... Done"
                    execute_command ${super_user} $ip "systemctl restart sshd 1>/dev/null 2>&1"
                    execute_command ${super_user} $ip "service sshd restart 1>/dev/null 2>&1"
                    [ $? -ne 0 ] && echo "$(date +"%Y-%m-%d %T") [WARNING] restart sshd service failed."
                else
                    echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/ssh/sshd_config\" found on $ip"
                    flag=0
                    break;
                fi
            else
                break;
            fi
            let count++
        done
        [ $flag -eq 1 ] && echo "[ERROR] change parameter [UsePAM] failed, will exit." && exit 1
    fi

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        file_num=`execute_command ${execute_user} $ip "ulimit -n 2>/dev/null"`
        if [ "$file_num"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ulimit.open files] is null (no less than: 65535) on $ip"
            flag=1
        elif [ $file_num -lt 65535 ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ulimit.open files] $file_num (no less than: 65535) on $ip"
            flag=1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.open files] $file_num on $ip"
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [ulimit.open files] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/security/limits.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.open files on $ip ..."
                execute_command ${super_user} $ip "echo \"
*       soft        nofile      655360
root    soft        nofile      655360
*       hard        nofile      655360
root    hard        nofile      655360\" >> /etc/security/limits.conf"
                execute_command ${super_user} $ip "/bin/rm -rf /etc/security/limits.d/*"
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.open files on $ip ... Done"
                [ $on_bmj -eq 1 ] && flag=0 && break
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/security/limits.conf\" found on $ip"
                flag=0
                break;
            fi
        else
            break;
        fi
        let count++
    done

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        proc_num=`execute_command ${execute_user} $ip "ulimit -u 2>/dev/null"`
        if [ "$proc_num"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ulimit.open proc] is null (no less than: 65535) on $ip"
            flag=1
        elif [ $proc_num -lt 65535 ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ulimit.open proc] $proc_num (no less than: 65535) on $ip"
            flag=1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.open proc] $proc_num on $ip"
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [ulimit.open proc] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/security/limits.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.open proc on $ip ..."
                execute_command ${super_user} $ip "echo \"
*       soft        nproc       655360
root    soft        nproc       655360
*       hard        nproc       655360
root    hard        nproc       655360\" >> /etc/security/limits.conf"
                execute_command ${super_user} $ip "/bin/rm -rf /etc/security/limits.d/*"
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.open proc on $ip ... Done"
                [ $on_bmj -eq 1 ] && flag=0 && break
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/security/limits.conf\" found on $ip"
                flag=0
                break;
            fi
        else
            break;
        fi
        let count++
    done

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        core_size=`execute_command ${execute_user} $ip "ulimit -c 2>/dev/null"`
        if [ "$core_size"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.core size] is null on $ip"
            flag=1
        elif [ "${core_size}"x != "unlimited"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.core size] $core_size (no unlimited) on $ip"
            flag=1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.core size] $core_size on $ip"
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [ulimit.core size] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/security/limits.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.core size on $ip ..."
                execute_command ${super_user} $ip "echo \"
*       soft        core        unlimited
root    soft        core        unlimited
*       hard        core        unlimited
root    hard        core        unlimited\" >> /etc/security/limits.conf"
                execute_command ${super_user} $ip "/bin/rm -rf /etc/security/limits.d/*"
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.core size on $ip ... Done"
                [ $on_bmj -eq 1 ] && flag=0 && break
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/security/limits.conf\" found on $ip"
                flag=0
                break;
            fi
        else
            break;
        fi
        let count++
    done

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        mem_lock=`execute_command ${execute_user} $ip "ulimit -l 2>/dev/null"`
        if [ "$mem_lock"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.mem lock] is null on $ip"
            flag=1
        elif [ ${mem_lock} -lt 50000000 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.mem lock] $mem_lock (less than 50000000) on $ip"
            flag=1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ulimit.mem lock] $mem_lock on $ip"
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [ulimit.mem lock] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/security/limits.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.mem lock on $ip ..."
                execute_command ${super_user} $ip "echo \"
*       soft        memlock     50000000
root    soft        memlock     50000000
*       hard        memlock     50000000
root    hard        memlock     50000000\" >> /etc/security/limits.conf"
                execute_command ${super_user} $ip "/bin/rm -rf /etc/security/limits.d/*"
                echo "$(date +"%Y-%m-%d %T") [INFO] change ulimit.mem lock on $ip ... Done"
                [ $on_bmj -eq 1 ] && flag=0 && break
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/security/limits.conf\" found on $ip"
                flag=0
                break;
            fi
        else
            break;
        fi
        let count++
    done

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        kernel_sem_value1=`execute_command ${super_user} $ip "sysctl kernel.sem 2>/dev/null |awk -F '=' '{print \\$2}'|awk '{print \\$1}'"`
        kernel_sem_value2=`execute_command ${super_user} $ip "sysctl kernel.sem 2>/dev/null |awk -F '=' '{print \\$2}'|awk '{print \\$2}'"`
        kernel_sem_value3=`execute_command ${super_user} $ip "sysctl kernel.sem 2>/dev/null |awk -F '=' '{print \\$2}'|awk '{print \\$3}'"`
        kernel_sem_value4=`execute_command ${super_user} $ip "sysctl kernel.sem 2>/dev/null |awk -F '=' '{print \\$2}'|awk '{print \\$4}'"`
        if [ "$kernel_sem_value1"x = ""x -o "$kernel_sem_value2"x = ""x  -o "$kernel_sem_value3"x = ""x -o "$kernel_sem_value4"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [kernel.sem] is null (no less than: 5010 641280 5010 256) on $ip"
            flag=1
        elif [ $kernel_sem_value1 -lt 5010 -o $kernel_sem_value2 -lt 641280 -o $kernel_sem_value3 -lt 5010 -o $kernel_sem_value4 -lt 256 ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [kernel.sem] $kernel_sem_value1 $kernel_sem_value2 $kernel_sem_value3 $kernel_sem_value4 (no less than: 5010 641280 5010 256) on $ip"
            flag=1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [kernel.sem] $kernel_sem_value1 $kernel_sem_value2 $kernel_sem_value3 $kernel_sem_value4 on $ip"
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [kernel.sem] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/sysctl.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change kernel.sem on $ip ..."
                execute_command ${super_user} $ip "echo \"
kernel.sem= 5010 641280 5010 256
fs.file-max=7672460
fs.aio-max-nr=1048576
net.core.rmem_default=262144
net.core.rmem_max=4194304
net.core.wmem_default=262144
net.core.wmem_max=4194304
net.ipv4.ip_local_port_range=9000 65500
net.ipv4.tcp_wmem=8192 65536 16777216
net.ipv4.tcp_rmem=8192 87380 16777216
vm.min_free_kbytes=512000
vm.vfs_cache_pressure=200
vm.swappiness=20
net.ipv4.tcp_max_syn_backlog=4096
net.core.somaxconn=4096\" >> /etc/sysctl.conf"
                echo "$(date +"%Y-%m-%d %T") [INFO] change kernel.sem on $ip ... Done"
                execute_command ${super_user} $ip "sysctl -p > /dev/null"
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/sysctl.conf\" found on $ip"
                flag=0
                break;
            fi
        else
            break;
        fi
        let count++
    done
    [ $flag -eq 1 ] && echo "[ERROR] change parameter [kernel.sem] failed, will exit." && exit 1

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        RemoveIPC=`execute_command ${super_user} $ip "cat /etc/systemd/logind.conf 2>/dev/null |grep ^RemoveIPC | tail -n 1"`
        RemoveIPC_values=`echo $RemoveIPC | awk -F '=' '{print $2}'`
        RemoveIPC_v=`echo ${RemoveIPC_values} | tr '[A-Z]' '[a-z]'`
        if [ "$RemoveIPC_v"x = "no"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [RemoveIPC] $RemoveIPC_v on $ip"
        elif [ "$RemoveIPC_v"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [WARNING] [RemoveIPC] is null on $ip"
            flag=1
        else
            echo "$(date +"%Y-%m-%d %T") [ERROR] [RemoveIPC] $RemoveIPC_v (should be: no) on $ip"
            flag=1
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [RemoveIPC] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/systemd/logind.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change RemoveIPC on $ip ..."
                execute_command ${super_user} $ip "sed \"s/^RemoveIPC[ ]*=/#RemoveIPC=/g\" /etc/systemd/logind.conf > /etc/systemd/config_temp"
                execute_command ${super_user} $ip "cat /etc/systemd/config_temp > /etc/systemd/logind.conf"
                execute_command ${super_user} $ip "/bin/rm -f /etc/systemd/config_temp"
                execute_command ${super_user} $ip "echo \"\" >> /etc/systemd/logind.conf"
                execute_command ${super_user} $ip "echo \"RemoveIPC=no\" >> /etc/systemd/logind.conf"
                echo "$(date +"%Y-%m-%d %T") [INFO] change RemoveIPC on $ip ... Done"
                [ $on_bmj -eq 0 ] && execute_command ${super_user} $ip "systemctl daemon-reload 1>/dev/null 2>&1"
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/systemd/logind.conf\" found on $ip"
                flag=0
                break;
            fi
        else
           break;
        fi
        let count++
    done
    [ $flag -eq 1 ] && echo "[ERROR] change parameter [RemoveIPC] failed, will exit." && exit 1

    count=0
    while [ $count -lt 3 ]
    do
        flag=0
        DefaultTasksAccounting=`execute_command ${super_user} $ip "cat /etc/systemd/system.conf  2>/dev/null | grep ^DefaultTasksAccounting | tail -n 1"`
        DefaultTasksAccounting_values=`echo $DefaultTasksAccounting | awk -F '=' '{print $2}'`
        DefaultTasksAccounting_v=`echo ${DefaultTasksAccounting_values} | tr '[A-Z]' '[a-z]'`

        if [ "$DefaultTasksAccounting_v"x = "no"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [DefaultTasksAccounting] $DefaultTasksAccounting_v on $ip"
        elif [ "$DefaultTasksAccounting_v"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [DefaultTasksAccounting] is null on $ip"
        else
            echo "$(date +"%Y-%m-%d %T") [ERROR] [DefaultTasksAccounting] $DefaultTasksAccounting_v (should be: no) on $ip"
            flag=1
        fi
        if [ $flag -eq 1 ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] the value of [DefaultTasksAccounting] is wrong, now will change it on $ip ..."
            execute_command ${super_user} $ip "test -f /etc/systemd/system.conf"
            if [ $? -eq 0 ];then
                echo "$(date +"%Y-%m-%d %T") [INFO] change DefaultTasksAccounting on $ip ..."
                execute_command ${super_user} $ip "sed \"s/^DefaultTasksAccounting[ ]*=/#DefaultTasksAccounting=/g\" /etc/systemd/system.conf > /etc/systemd/config_temp"
                execute_command ${super_user} $ip "cat /etc/systemd/config_temp > /etc/systemd/system.conf"
                execute_command ${super_user} $ip "/bin/rm -f /etc/systemd/config_temp"
                execute_command ${super_user} $ip "echo \"\" >> /etc/systemd/system.conf"
                execute_command ${super_user} $ip "echo \"DefaultTasksAccounting=no\" >> /etc/systemd/system.conf"
                echo "$(date +"%Y-%m-%d %T") [INFO] change DefaultTasksAccounting on $ip ... Done"
                [ $on_bmj -eq 0 ] && execute_command ${super_user} $ip "systemctl daemon-reload 1>/dev/null 2>&1"
            else
                echo "$(date +"%Y-%m-%d %T") [WARNING] there is no file \"/etc/systemd/system.conf\" found on $ip"
                flag=0
                break;
            fi
        else
            break;
        fi
        let count++
    done
    [ $flag -eq 1 ] && echo "[ERROR] change parameter [DefaultTasksAccounting] failed, will exit." && exit 1

    cron_path=`execute_command ${super_user} $ip "which crond 2>/dev/null"`
    if [ "$cron_path"x = ""x ]
    then
        cron_path=`execute_command ${super_user} $ip "which cron 2>/dev/null"`
        if [ "$cron_path"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [WARNING] Can not use command [which] to find [cron/crond service], it may not exist, please set cron/crond service active on $ip!!!"
        else
            cron_name=cron
        fi
    else
        cron_name=crond
    fi

    limit=`execute_command ${super_user} $ip "systemctl  status \"$cron_name\" 2>/dev/null | tr '[A-Z]' '[a-z]' | sed -n \"/tasks: [0-9]* (limit: [0-9]*)/p\""`
    if [ "$limit"x != ""x ]
    then
        tasks=`echo "$limit" | sed "s/.*limit: \(.*\))$/\1/g"`
        if [ "$tasks"x = ""x ]
        then
            echo "$(date +"%Y-%m-%d %T") [INFO] [systemd limit] is null (no less than: 65535) on $ip"
        elif [ $tasks -lt 65535 ]
        then
            echo "$(date +"%Y-%m-%d %T") [WARNING] [systemd limit] $tasks (no less than: 65535) on $ip"
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [systemd limit] $tasks on $ip"
        fi
    fi

    SELINUX=`execute_command ${super_user} $ip "getenforce 2>/dev/null"`
    SELINUX_values=`echo ${SELINUX} | tr '[A-Z]' '[a-z]'`

    if [ "$SELINUX_values"x = "disabled"x -o "$SELINUX_values"x = "permissive"x ]
    then
        echo "$(date +"%Y-%m-%d %T") [INFO] [SELINUX] $SELINUX_values on $ip"
    elif [ "$SELINUX_values"x = ""x ]
    then
        echo "$(date +"%Y-%m-%d %T") [INFO] [SELINUX] is null on $ip"
    else
        echo "$(date +"%Y-%m-%d %T") [WARNING] [SELINUX] $SELINUX_values (should be: disabled or permissive) on $ip"
    fi

    execute_command ${super_user} $ip "service iptables status 1>/dev/null 2>&1"
    iptables_flag=$?

    execute_command ${super_user} $ip "service firewalld status 1>/dev/null 2>&1"
    firewalld_flag=$?

    execute_command ${super_user} $ip "service ufw status 1>/dev/null 2>&1"
    ufw_flag=$?

    if [ "$iptables_flag"x = "0"x -o "$firewalld_flag"x = "0"x -o "$ufw_flag"x = "0"x ]
    then
        echo "$(date +"%Y-%m-%d %T") [WARNING] [firewall] up (should be: down or add port rules) on $ip"
    else
        echo "$(date +"%Y-%m-%d %T") [INFO] [firewall] down on $ip"
    fi

    mem=`execute_command ${super_user} $ip "cat /proc/meminfo |grep -w \"MemFree\" |awk '{print \\$2}'"`
    if [ "$mem"x = ""x ]
    then
        echo "$(date +"%Y-%m-%d %T") [WARNING] [The memory] is null (no less than 1G) on $ip"
    elif [ $mem -lt 1048576 ]
    then
        echo "$(date +"%Y-%m-%d %T") [WARNING] [The memory] $mem kb (no less than 1G) on $ip"
    else
        echo "$(date +"%Y-%m-%d %T") [INFO] [The memory] OK on $ip"
    fi

    if [ $on_bmj -eq 0 ]
    then
        df_path=/home/$execute_user
    else
        df_path=/opt
    fi

    hard_disk=`execute_command ${super_user} $ip "df $df_path -P 2>/dev/null |head -n 2| tail -n +2|awk '{print \\$4}'"`
    if [ "$hard_disk"x = ""x ]
    then
        echo "$(date +"%Y-%m-%d %T") [ERROR] [The hard disk] is null (no less than 1G) on $ip"
        exit 1
    elif [ $hard_disk -lt 1048576 ]
    then
        echo "$(date +"%Y-%m-%d %T") [ERROR] [The hard disk] $hard_disk (no less than 1G) on $ip"
        exit 1
    else
        echo "$(date +"%Y-%m-%d %T") [INFO] [The hard disk] OK on $ip"
    fi

    if [ ${is_ipv6} -eq 0 ]
    then
        ping_c=`execute_command ${super_user} $ip "ls $ping_path/ping 2>/dev/null"`
        ping_exist=$?
        if [ "$ping_exist"x != "0"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ping command path] $ping_path incorrect on $ip"
            exit 1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ping command path] OK on $ip"
        fi
    else
        ping_c=`execute_command ${super_user} $ip "ls $ping_path/ping6 2>/dev/null"`
        ping_exist=$?
        if [ "$ping_exist"x != "0"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ping6 command path] $ping_path incorrect on $ip"
            exit 1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ping6 command path] OK on $ip"
        fi
    fi
    execute_command ${super_user} $ip "/bin/cp --version >/dev/null 2>&1"
    cp_exist=$?
    if [ "$cp_exist"x != "0"x ]
    then
        echo "$(date +"%Y-%m-%d %T") [ERROR] [/bin/cp --verison] execute failed on $ip"
        exit 1
    else
        echo "$(date +"%Y-%m-%d %T") [INFO] [/bin/cp --version] on $ip OK"
    fi

    if [ "$virtual_ip"x = ""x ]
    then
        echo "$(date +"%Y-%m-%d %T") [INFO] [Virtual IP] Not configured on $ip"
    else
        vip=${virtual_ip%%/*}
        ip_c=`execute_command ${super_user} $ip "ls $ipaddr_path/ip 2>/dev/null"`
        ip_exist=$?
        if [ "$ip_exist"x != "0"x ]
        then
            echo "$(date +"%Y-%m-%d %T") [ERROR] [ip command path] $ipaddr_path incorrect on $ip"
            exit 1
        else
            echo "$(date +"%Y-%m-%d %T") [INFO] [ip command path] on $ip OK"
        fi

        if [ "${is_ipv6}"x = "0"x ]; then
            regex="\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\b"
            ckip=`echo $vip | egrep $regex | wc -l`
            if [ $ckip -eq 0 ]
            then
                echo "$(date +"%Y-%m-%d %T") [ERROR] [Virtual IP] $virtual_ip (should be: IP)"
                exit 1
            else
                if [ "$function_name"x == "install"x ]
                then
                    vip_ping=`${ping_path}/ping $vip -c 3 2>/dev/null |grep -w "received" |awk '{print $4}'`
                    vip_exist=`${ipaddr_path}/ip addr |grep -w "$vip"|wc -l`
                    if [ "$vip_ping"x != "0"x -a "$vip_exist"x = "0"x ]
                    then
                        echo "$(date +"%Y-%m-%d %T") [ERROR] [Virtual IP] $virtual_ip Cannot use"
                        exit 1
                    else
                        echo "$(date +"%Y-%m-%d %T") [INFO] [Virtual IP] $virtual_ip OK"
                    fi
                fi
            fi
        else
            vip_ping=`${ping_path}/ping6 $vip -c 3 2>/dev/null |grep -w "received" |awk '{print $4}'`
            vip_exist=`${ipaddr_path}/ip addr |grep -w "$vip"|wc -l`
            if [ "$vip_ping"x != "0"x -a "$vip_exist"x = "0"x ]
            then
                echo "$(date +"%Y-%m-%d %T") [ERROR] [Virtual IP] $virtual_ip Cannot use"
                exit 1
            else
                echo "$(date +"%Y-%m-%d %T") [INFO] [Virtual IP] $virtual_ip OK"
            fi
        fi
    fi
}

function create_witness_node()
{
    execute_command ${execute_user} ${witness_ip} "${sys_bindir}/initdb -D ${data_directory} -U $db_user -A ${db_auth} -x '$db_password' -m $db_mode ${witness_initdb_options}"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] end to init the database on \"${witness_ip}\" ... OK"

    # config the database configuration file kingbase.conf
    echo "[INSTALL] wirte the kingbase.conf on \"${witness_ip}\" ..."
    if [ $on_bmj -eq 0 ]
    then
        execute_command ${execute_user} ${witness_ip} "sed -i -e \"/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/\" ${data_directory}/kingbase.conf"
    else
        execute_command ${execute_user} ${witness_ip} "sed -e \"/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/\" ${data_directory}/kingbase.conf > ${data_directory}/kingbase.conf.tmp && cat ${data_directory}/kingbase.conf.tmp > ${data_directory}/kingbase.conf && /bin/rm -rf ${data_directory}/kingbase.conf.tmp"
fi

    execute_command ${execute_user} ${witness_ip} "echo \"\" >> ${data_directory}/kingbase.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"include_if_exists = 'es_rep.conf'\" >> ${data_directory}/kingbase.conf"
    echo "[INSTALL] wirte the kingbase.conf on \"${witness_ip}\" ... OK"

    execute_command ${execute_user} ${witness_ip} "test ! -f ${data_directory}/es_rep.conf && touch ${data_directory}/es_rep.conf"

    echo "[INSTALL] wirte the es_rep.conf on \"${witness_ip}\" ..."
    execute_command ${execute_user} ${witness_ip} "echo \"listen_addresses = '*'\" > ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"port = ${db_port}\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"full_page_writes = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"wal_log_hints = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"wal_keep_segments = 512\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"max_connections = 100\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"wal_level = replica\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"max_replication_slots = 32\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"logging_collector = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"log_destination='csvlog'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"control_file_copy = '${install_dir}/copy_file'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"max_replication_slots = 32\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"log_checkpoints = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"log_replication_commands = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"wal_compression = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"synchronous_commit = remote_apply\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"max_prepared_transactions = 100\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"shared_buffers = 512MB\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"fsync = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"timezone = 'PRC'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"lc_messages = 'C'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"lc_monetary = 'C'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"lc_numeric = 'C'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"lc_time = 'C'\" >> ${data_directory}/es_rep.conf"

	if [ -n "${tcp_keepalives_idle}" ]; then
		execute_command ${execute_user} ${witness_ip} "echo \"tcp_keepalives_idle = ${tcp_keepalives_idle}\" >> ${data_directory}/es_rep.conf"
	fi

	if [ -n "${tcp_keepalives_interval}" ]; then
		execute_command ${execute_user} ${witness_ip} "echo \"tcp_keepalives_interval = ${tcp_keepalives_interval}\" >> ${data_directory}/es_rep.conf"
	fi

	if [ -n "${tcp_keepalives_count}" ]; then
		execute_command ${execute_user} ${witness_ip} "echo \"tcp_keepalives_count = ${tcp_keepalives_count}\" >> ${data_directory}/es_rep.conf"
	fi

    if [ -n "${tcp_user_timeout}" ]; then
	    execute_command ${execute_user} ${witness_ip} "echo \"tcp_user_timeout = ${tcp_user_timeout}\" >> ${data_directory}/es_rep.conf"
    fi

    if [ -n "$wal_sender_timeout" ]; then
        execute_command ${execute_user} ${witness_ip} "echo \"wal_sender_timeout = ${wal_sender_timeout}\" >> ${data_directory}/es_rep.conf"
    fi
   
    if [ -n "${wal_receiver_timeout}" ]; then
        execute_command ${execute_user} ${witness_ip} "echo \"wal_receiver_timeout = ${wal_receiver_timeout}\" >> ${data_directory}/es_rep.conf"
    fi
   

    echo "[INSTALL] wirte the es_rep.conf on \"${witness_ip}\" ... OK"

    # config the database identity authentication file sys_hba.conf
    echo "[INSTALL] wirte the sys_hba.conf on \"${witness_ip}\" ..."
    if [ $on_bmj -eq 0 ]
    then
        execute_command ${execute_user} ${witness_ip} "sed -i -e \"s/\(.*0\.0\.0\.0\/0\(.*\)$\)/#\1/g\" ${data_directory}/sys_hba.conf"
    else
        execute_command ${execute_user} ${witness_ip} "sed -e \"s/\(.*0\.0\.0\.0\/0\(.*\)$\)/#\1/g\" ${data_directory}/sys_hba.conf > ${data_directory}/sys_hba.conf.tmp && cat ${data_directory}/sys_hba.conf.tmp > ${data_directory}/sys_hba.conf && /bin/rm -rf ${data_directory}/sys_hba.conf.tmp"
    fi

    execute_command ${execute_user} ${witness_ip} "echo \"host    all             all             0.0.0.0/0               ${db_auth}\" >> ${data_directory}/sys_hba.conf"
    execute_command ${execute_user} ${witness_ip} "echo \"host    replication     all             0.0.0.0/0               ${db_auth}\" >> ${data_directory}/sys_hba.conf"

    echo "[INSTALL] wirte the sys_hba.conf on \"${witness_ip}\" ... OK"

    echo "[INSTALL] start up the database on \"${witness_ip}\" ..."
    echo "[INSTALL] ${sys_bindir}/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start"
    execute_command ${execute_user} ${witness_ip} "${sys_bindir}/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] start up the database on \"${witness_ip}\" ... OK"

    # create the database and user used by repmgr, and regitser the witness node
    echo "[INSTALL] create the database \"esrep\" and user \"esrep\" for repmgr ..."
    execute_command ${execute_user} ${witness_ip} "${sys_bindir}/ksql -d test -U ${db_user} -p ${db_port} -c \"create database esrep;\""
    execute_command ${execute_user} ${witness_ip} "${sys_bindir}/ksql -d test -U ${db_user} -p ${db_port} -c \"create user esrep with superuser password '${esrep_passwd_base64}';\""
    echo "[INSTALL] create the database \"esrep\" and user \"esrep\" for repmgr ... OK"
    echo "[INSTALL] register the witness on \"${witness_ip}\" ..."
    execute_command ${execute_user} ${witness_ip} "${sys_bindir}/repmgr witness register -h ${primary_host} -p ${db_port}"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] register the witness on \"${witness_ip}\" ... OK"
}
function drop_witness_node()
{
    echo "[`date`] [INFO] ${sys_bindir}/repmgr witness unregister --node-id=$node_id ..."
    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr witness unregister --node-id=$node_id"
    [ $? -ne 0 ] && exit 1
    echo "[`date`] [INFO] ${sys_bindir}/repmgr witness unregister --node-id=$node_id ...OK"
    sshstopwitness $shrink_ip
    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show"
}

function install()
{
    usersetip=$*
    pre_exe
    [ $? -ne 0 ] && exit 1

    local should_exit=0

    if [ "${primary_host}"x = ""x ]
    then
        primary_host="${all_ip[0]}"
    fi

    # ssh to check if every host could be reached
    echo "[RUNNING] check if the host can be reached ..."
    for ip in ${all_ip[@]}
    do
        test_ssh $ip
        if [ $? -ne 0 ]
        then
            should_exit=1
            echo "[RUNNING] can not connect to \"${ip}\" by '${binary_local}' on port '${port_local}', please check it."
            break
        else
            echo "[RUNNING] success connect to the target \"${ip}\" ..... OK"
        fi
    done
    [ $should_exit -eq 1 ] && exit 1

    if [ "${virtual_ip}"x != ""x ]
    then
        local i=0
        local ip_count=0
        echo "[RUNNING] check the [net_device_ip] on dev [net_device] ..."
        for ip in ${net_device_ip[@]}
        do
            ip_count=0
            if [ ${#net_device[@]} -eq 1 ]
            then
                ip_count=`execute_command ${super_user} ${all_ip[$i]} "${ipaddr_path}/ip address show dev ${net_device} | grep -w \"${ip}\" | wc -l"`
                if [ $? -ne 0 ] || [ ${ip_count} -eq 0 ]
                then
                    echo "[ERROR] ${ip} does not on host \"${all_ip[$i]}\" on dev \"${net_device}\""
                    should_exit=1
                else
                    echo "[RUNNING] ${ip} on host \"${all_ip[$i]}\" on dev \"${net_device}\" ..... OK"
                fi
            else
                ip_count=`execute_command ${super_user} ${all_ip[$i]} "${ipaddr_path}/ip address show dev ${net_device[$i]} | grep -w \"${ip}\" | wc -l"`
                if [ $? -ne 0 ] || [ ${ip_count} -eq 0 ]
                then
                    echo "[ERROR] ${ip} does not on host \"${all_ip[$i]}\" on dev \"${net_device[$i]}\""
                    should_exit=1
                else
                    echo "[RUNNING] ${ip} on host \"${all_ip[$i]}\" on dev \"${net_device[$i]}\" ..... OK"
                fi
            fi

            let i++
        done
        [ $should_exit -eq 1 ] && exit 1
    fi

    local db_running=""
    # check if there is kingbase running on the host
    echo "[RUNNING] check the db is running or not..."
    for ip in ${all_ip[@]}
    do
        db_running=`execute_command ${super_user} $ip "netstat -apn 2>/dev/null|grep -w \"${db_port}\"|wc -l"`
        if [ $? -ne 0 -o "${db_running}"x != "0"x ]
        then
            if [ $on_bmj -eq 1 ]
            then
                execute_command ${execute_user} $ip "${sys_bindir}/sys_ctl -D ${data_directory} stop 2>/dev/null"
            else
                should_exit=1
                echo "[ERROR] the db on \"${ip}:${db_port}\" is running, please stop it first."
            fi
        else
            echo "[RUNNING] the db is not running on \"${ip}:${db_port}\" ..... OK"
        fi
    done
    [ $should_exit -eq 1 ] && exit 1

    if [ $deploy_by_sshd -eq 1 -a $use_scmd -eq 1 ]
    then
        # check if there is sys_securecmdd running on the host
        echo "[RUNNING] check the sys_securecmdd is running or not..."
        for ip in ${all_ip[@]}
        do
            es_running=`execute_command ${super_user} $ip "netstat -apn 2>/dev/null|grep -w \"${scmd_port}\"|wc -l"`
            if [ $? -ne 0 -o "${es_running}"x != "0"x ]
            then
                should_exit=1
                echo "[ERROR] the sys_securecmdd on \"${ip}:${scmd_port}\" is running, please stop it first."
            else
                echo "[RUNNING] the sys_securecmdd is not running on \"${ip}:${scmd_port}\" ..... OK"
            fi
        done
        [ $should_exit -eq 1 ] && exit 1
    elif [ $deploy_by_sshd -eq 0 -a $on_bmj -eq 0 ]
    then
        # check if there is ~/.es for execute_user
        echo "[RUNNING] check the ~/.es for ${execute_user} ..."
        local es_home_path="/home/${execute_user}/.es"
        for ip in ${all_ip[@]}
        do
            execute_command ${super_user} $ip "test -d ${es_home_path} && chown -R ${execute_user}:${execute_user} ${es_home_path}"
            if [ $? -ne 0 ]
            then
                execute_command ${super_user} $ip "cp -rf /root/.es ${es_home_path} && chown -R ${execute_user}:${execute_user} ${es_home_path}"
                if [ $? -ne 0 ]
                then
                    should_exit=1
                    echo "[ERROR] failed to copy /root/.es to ${es_home_path} on \"${ip}\"."
                else
                    echo "[RUNNING] copy /root/.es to ${es_home_path} on \"${ip}\" ..... OK"
                fi
            else
                echo "[RUNNING] the ${es_home_path} is already exists on \"${ip}\" ..... OK"
            fi
        done
        [ $should_exit -eq 1 ] && exit 1
    fi

    # check if data directory exists
    echo "[RUNNING] check if the install dir is already exist ..."
    for ip in ${all_ip[@]}
    do
        execute_command ${execute_user} $ip "test ! -e ${install_dir}"
        if [ $? -ne 0 ]
        then
            if [ $on_bmj -eq 0 ]
            then
                if [ $deploy_by_sshd -eq 1 ]
                then
                    should_exit=1
                    echo "[ERROR] the install dir \"${install_dir}\" on \"${ip}\" is already exist, please remove it first."
                else
                    echo "[RUNNING] when deploy_by_sshd=0, the install dir \"${install_dir}\" on \"${ip}\" is right .... OK"
                fi
            else
                echo "[RUNNING] the install dir \"${install_dir}\" on \"${ip}\" of BMJ is right .... OK"
            fi
        else
            if [ $on_bmj -eq 0 ]
            then
                if [ $deploy_by_sshd -eq 1 ]
                then
                    echo "[RUNNING] the install dir is not exist on \"${ip}\" ..... OK"
                else
                    should_exit=1
                    echo "[ERROR] when deploy_by_sshd=0, there have not installed kingbase database on \"${ip}\" yet ..... failed"
                fi
            else
                should_exit=1
                echo "[ERROR] there have not installed kingbase database on \"${ip}\" of BMJ yet ..... failed"
            fi
        fi
    done
    [ $should_exit -eq 1 ] && exit 1

    if [ "${waldir}"x != ""x ]
    then
        echo "[RUNNING] check if the waldir is already exist and not empty ..."
        for ip in ${all_ip[@]}
        do
            content=`execute_command ${super_user} $ip "test ! -e $waldir || ls -A $waldir"`
            if [ $? -ne 0 -o "${content}"x != ""x ]
            then
                echo "[ERROR] the waldir \"$waldir\" is not empty on ${ip}, need remove or empty the directory"
                should_exit=1
            else
                echo "[RUNNING] the waldir is empty or not exist on \"${ip}\" ..... OK"
            fi
        done
        [ $should_exit -eq 1 ] && exit 1
    fi

    for ip in ${all_ip[@]}
    do
        check_and_change_system "$ip"
    done

    # create install directory
    if [ $deploy_by_sshd -eq 1 ]
    then
        echo "[INSTALL] create the install dir \"${install_dir}\" on every host ..."
        for ip in ${all_ip[@]}
        do
            execute_command ${execute_user} $ip "mkdir -p ${install_dir}"
            if [ $? -ne 0 ]
            then
                echo "[INSTALL] failed to create the install dir \"${install_dir}\" on \"${ip}\"."
                exit 1
            else
                echo "[INSTALL] success to create the install dir \"${install_dir}\" on \"${ip}\" ..... OK"
            fi
        done

        # unzip the zip package to ${install_dir}
        echo "[INSTALL] decompress the \"${zip_package}\" to \"${install_dir}\""
        if [ $name_zip -eq 1 ]
        then
            execute_command ${execute_user} ${primary_host} "unzip -q -o ${zip_package} -d ${install_dir} 1>/dev/null"
            if [ $? -ne 0 ]
            then
                echo "[INSTALL] failed to decompress the \"${zip_package}\" to \"${install_dir}\" on \"${primary_host}\"."
                exit 1
            else
                echo "[INSTALL] success to decompress the \"${zip_package}\" to \"${install_dir}\" on \"${primary_host}\"..... OK"
            fi
        elif [ $name_tar -eq 1 ]
        then
            execute_command ${execute_user} ${primary_host} "tar -xvf ${zip_package} -C ${install_dir} 1>/dev/null"
            if [ $? -ne 0 ]
            then
                echo "[INSTALL] failed to decompress the \"${zip_package}\" to \"${install_dir}\" on \"${primary_host}\"."
                exit 1
            else
                echo "[INSTALL] success to decompress the \"${zip_package}\" to \"${install_dir}\" on \"${primary_host}\"..... OK"
            fi
        elif [ $name_gz -eq 1 ]
        then
            execute_command ${execute_user} ${primary_host} "tar -zxvf ${zip_package} -C ${install_dir} 1>/dev/null"
            if [ $? -ne 0 ]
            then
                echo "[INSTALL] failed to decompress the \"${zip_package}\" to \"${install_dir}\" on \"${primary_host}\"."
                exit 1
            else
                echo "[INSTALL] success to decompress the \"${zip_package}\" to \"${install_dir}\" on \"${primary_host}\"..... OK"
            fi
        fi
    fi

    # check the directory
    execute_command ${execute_user} ${primary_host} "test ! -d ${install_dir}/bin"
    if [ $? -eq 0 ]
    then
        echo "[INSTALL] the target dir of decompress is not correct, there is no dir \"${install_dir}/bin\" on \"${primary_host}\""
        exit 1
    fi

    # create directory archive、etc、log and create file repmgr.conf
    if [ $deploy_by_sshd -eq 1 ]
    then
        echo "[INSTALL] create the dir \"${install_dir}/etc\" on primary host"
        execute_command ${execute_user} ${primary_host} "test ! -d ${install_dir}/etc && mkdir ${install_dir}/etc"
        execute_command ${execute_user} ${primary_host} "test ! -d ${sys_logdir} && mkdir ${sys_logdir}"
        execute_command ${execute_user} ${primary_host} "test ! -d ${install_dir}/archive && mkdir ${install_dir}/archive"
        execute_command ${execute_user} ${primary_host} "test ! -f ${install_dir}/etc/repmgr.conf && touch ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} ${primary_host} "test ! -f ${install_dir}/etc/all_nodes_tools.conf && touch ${install_dir}/etc/all_nodes_tools.conf"

        # copy the whole install directory to other hosts
        echo "[INSTALL] scp the dir \"${install_dir}\" to other host"
        for ip in ${all_ip[@]}
        do
            [ "${primary_host}"x != ""x -a "${primary_host}"x = "${ip}"x ] && continue

            echo "[INSTALL] try to copy the install dir \"${install_dir}\" to \"${ip}\" ....."
            execute_command ${execute_user} ${primary_host} "scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r ${install_dir}/* ${execute_user}@[${ip}]:${install_dir}"
            if [ $? -ne 0 ]
            then
                echo "[INSTALL] failed to scp the install dir \"${install_dir}\" to \"${ip}\"."
                exit 1
            else
                echo "[INSTALL] success to scp the install dir \"${install_dir}\" to \"${ip}\" ..... OK"
            fi
        done
    else
        echo "[INSTALL] create the dir \"${install_dir}/etc\" on all host"
        for ip in ${all_ip[@]}
        do
            execute_command ${execute_user} ${ip} "test ! -d ${install_dir}/etc && mkdir ${install_dir}/etc"
            execute_command ${execute_user} ${ip} "test ! -d ${sys_logdir} && mkdir ${sys_logdir}"
            execute_command ${execute_user} ${ip} "test ! -d ${install_dir}/archive && mkdir ${install_dir}/archive"
            execute_command ${execute_user} ${ip} "test ! -f ${install_dir}/etc/repmgr.conf && touch ${install_dir}/etc/repmgr.conf"
            execute_command ${execute_user} ${ip} "test ! -f ${install_dir}/etc/all_nodes_tools.conf && touch ${install_dir}/etc/all_nodes_tools.conf"
        done
    fi

    # change the auth of bin dir
    if [ $on_bmj -eq 0 ]
    then
        for ip in ${all_ip[@]}
        do
            echo "[INSTALL] change the auth of bin directory on $ip ..."
            execute_command ${super_user} $ip "chmod -R 0755 ${sys_bindir}"
            [ $? -ne 0 ] && echo "[WARNING] change the auth on $ip failed."
        done
    fi

    # if VIP is set, change the auth of ip、arping
    if [ "${virtual_ip}"x != ""x  -a $on_bmj -eq 0 ]
    then
        echo "[RUNNING] chmod u+s for \"${ipaddr_path}\" and \"${arping_path}\""
        for ip in ${all_ip[@]}
        do
            execute_command ${super_user} $ip "chmod u+s ${ipaddr_path}/ip"
            if [ $? -ne 0 ]
            then
                should_exit=1
                echo "[RUNNING] can not execute \"chmod u+s ${ipaddr_path}/ip\" on \"${ip}\"."
                break
            else
                echo "[RUNNING] chmod u+s ${ipaddr_path}/ip on \"${ip}\" ..... OK"
            fi

            execute_command ${super_user} $ip "chown -R ${super_user}:${super_user} ${arping_path}/arping"
            execute_command ${super_user} $ip "chmod u+s ${arping_path}/arping"
            if [ $? -ne 0 ]
            then
                should_exit=1
                echo "[RUNNING] can not execute \"chmod u+s ${arping_path}/arping\" on \"${ip}\"."
                break
            else
                echo "[RUNNING] chmod u+s ${arping_path}/arping on \"${ip}\" ..... OK"
            fi
        done
        [ $should_exit -eq 1 ] && exit 1
    fi

    # check license path
    local num=0
    if [ $deploy_by_sshd -eq 1 ]
    then
        local scp_ret=0
        local ln_ret=0
        for ip in ${all_ip[@]}
        do
            scp_ret=0
            ln_ret=0
            if [ $license_num -eq 1 ]
            then
                #copy license.dat to install_dir
                echo "[INSTALL] check license_file \"${license_file}\""
                if [ -f ${license_path}/${license_file} ]
                then
                    if [ $? -ne 0 ]
                    then
                        echo "[INSTALL] Cannot access license_file: ${license_path}/${license_file}"
                        exit 1
                    else
                        echo "[INSTALL] success to access license_file: ${license_path}/${license_file}"
                    fi
                fi
                echo "[INSTALL] Copy license to ${install_dir}/../: ${license_file}"
                execute_command ${execute_user} ${primary_host} "scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r ${license_path}/${license_file} ${execute_user}@[${ip}]:${install_dir}/../"
                scp_ret=$?
                if [ ${license_file} != "license.dat" ]
                then
                    execute_command ${execute_user} $ip "ln -s ${install_dir}/../${license_file} ${sys_bindir}/../../license.dat"
                    ln_ret=$?
                fi
                if [ $scp_ret -ne 0 -o $ln_ret -ne 0 ]
                then
                    echo "[INSTALL] failed to copy ${license_path}/${license_file} to $install_dir/../ on $ip"
                    exit 1
                else
                    echo "[INSTALL] success to copy ${license_path}/${license_file} to $install_dir/../ on $ip"
                fi
            else
                #copy license.dat to install_dir
                echo "[INSTALL] check license_file \"${license_path}/${license_file[$num]}\""
                if [ -f ${license_path}/${license_file[$num]} ]
                then
                    if [ $? -ne 0 ]
                    then
                        echo "[INSTALL] Cannot access license_file: ${license_path}/${license_file[$num]}"
                        exit 1
                    else
                        echo "[INSTALL] success to access license_file: ${license_path}/${license_file[$num]}"
                    fi
                fi
                echo "[INSTALL] Copy license to ${install_dir}/../: ${license_path}/${license_file[$num]} on $ip"
                execute_command ${execute_user} ${primary_host} "scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r ${license_path}/${license_file[$num]} ${execute_user}@[${ip}]:${install_dir}/../"
                scp_ret=$?
                execute_command ${execute_user} $ip "ln -s ${install_dir}/../${license_file[$num]} ${sys_bindir}/../../license.dat"
                ln_ret=$?
                if [ $scp_ret -ne 0 -o $ln_ret -ne 0 ]
                then
                    echo "[INSTALL] failed to copy ${license_path}/${license_file[$num]} to $install_dir/../ on $ip"
                    exit 1
                else
                    echo "[INSTALL] success to copy ${license_path}/${license_file[$num]} to $install_dir/../ on $ip"
                fi
            fi
            let num++
        done
    elif [ $on_bmj -eq 1 ]
    then
        for ip in ${all_ip[@]}
        do
            execute_command ${execute_user} $ip "test -f $license_path"
            if [ $? -eq 0 ]
            then
                echo "[INSTALL] check license_file \"${license_path}\" on $ip .... ok"
            else
                echo "[INSTALL] check license_file \"${license_path}\" on $ip .... failed"
                exit 1
            fi
        done
    else
        for ip in ${all_ip[@]}
        do
            execute_command ${execute_user} ${ip} "test ! -f ${sys_bindir}/license.dat && test ! -f ${sys_bindir}/../../license.dat"
            if [ $? -eq 1 ]
            then
                echo "[INSTALL] check license_file \"${sys_bindir}/license.dat\" or \"${sys_bindir}/../../license.dat\" on $ip .... ok"
            else
                echo "[INSTALL] check license_file \"${sys_bindir}/license.dat\" or \"${sys_bindir}/../../license.dat\" on $ip .... failed"
                exit 1
            fi
        done
    fi

    # config sys_securecmdd and start it
    if [ $deploy_by_sshd -eq 1 -a $use_scmd -eq 1 ]
    then
        for ip in ${all_ip[@]}
        do
            echo "[RUNNING] config sys_securecmdd and start it ..."
            echo "[RUNNING] config the sys_securecmdd port to ${scmd_port} ..."
            execute_command ${execute_user} $ip "sed -i \"/^scmd_port[ ]*=/cscmd_port=${scmd_port}\" ${sys_bindir}/../share/sys_HAscmdd.conf"
            if [ $? -ne 0 ]
            then
                echo "[ERROR] config the sys_securecmdd port failed on $ip"
                exit 1
            else
                echo "[RUNNING] success to config the sys_securecmdd port on $ip ... OK"
            fi
            execute_command ${super_user} $ip "${sys_bindir}/sys_HAscmdd.sh init"
            if [ $? -ne 0 ]
            then
                echo "[ERROR] config sys_securecmdd failed on $ip"
                exit 1
            else
                echo "[RUNNING] success to config sys_securecmdd on $ip ... OK"
            fi

            execute_command ${super_user} $ip "${sys_bindir}/sys_HAscmdd.sh start"
            if [ $? -ne 0 ]
            then
                echo "[ERROR] start sys_securecmdd failed on $ip"
                exit 1
            else
                echo "[RUNNING] success to start sys_securecmdd on $ip ... OK"
            fi
        done
    fi

    echo "[RUNNING] check if the host can be reached between all nodes ..."
    for ip1 in ${all_ip[@]}
    do
        test_connect $ip1
        if [ $? -ne 0 ]
        then
            echo "[RUNNING] can not connect to ${ip1} from current node by '${binary_local}' on port '${port_local}'"
            should_exit=1
            continue
        else
            echo "[RUNNING] success connect to \"${ip1}\" from current node by '${binary_local}' ..... OK"
        fi

        for ip2 in ${all_ip[@]}
        do
            test_connect $ip1 $ip2
            if [ $? -ne 0 ]
            then
                echo "[RUNNING] can not connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}' on port '${port_remote}'"
                should_exit=1
            else
                echo "[RUNNING] success connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}' ..... OK"
            fi
        done
    done
    [ $should_exit -eq 1 ] && exit 1

    # init the database
    echo "[INSTALL] begin to init the database on \"${primary_host}\" ..."
    if [ $on_bmj -eq 1 ]
    then
        for ip in ${all_ip[@]}
        do
            execute_command ${execute_user} $ip "test ! -e ${data_directory}"
            if [ $? -ne 0 ]
            then
                echo "[RUNNING] the data dir \"${data_directory}\" on \"${ip}\" is already exist, please move it first."
                exit 1
            fi
        done
    fi

    execute_command ${execute_user} ${primary_host} "${sys_bindir}/initdb -D ${data_directory} -U $db_user -A ${db_auth} -x '$db_password' -m $db_mode ${initdb_options}"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] end to init the database on \"${primary_host}\" ... OK"

    # config the database configuration file kingbase.conf
    echo "[INSTALL] wirte the kingbase.conf on \"${primary_host}\" ..."
    if [ $on_bmj -eq 0 ]
    then
        execute_command ${execute_user} ${primary_host} "sed -i -e \"/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/\" ${data_directory}/kingbase.conf"
    else
        execute_command ${execute_user} ${primary_host} "sed -e \"/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/\" ${data_directory}/kingbase.conf > ${data_directory}/kingbase.conf.tmp && cat ${data_directory}/kingbase.conf.tmp > ${data_directory}/kingbase.conf && /bin/rm -rf ${data_directory}/kingbase.conf.tmp"
    fi
    execute_command ${execute_user} ${primary_host} "echo \"\" >> ${data_directory}/kingbase.conf"
    execute_command ${execute_user} ${primary_host} "echo \"include_if_exists = 'es_rep.conf'\" >> ${data_directory}/kingbase.conf"
    echo "[INSTALL] wirte the kingbase.conf on \"${primary_host}\" ... OK"

    execute_command ${execute_user} ${primary_host} "test ! -f ${data_directory}/es_rep.conf && touch ${data_directory}/es_rep.conf"

    echo "[INSTALL] wirte the es_rep.conf on \"${primary_host}\" ..."
    execute_command ${execute_user} ${primary_host} "echo \"listen_addresses = '*'\" > ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"port = ${db_port}\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"full_page_writes = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"wal_log_hints = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"max_wal_senders = 32\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"wal_keep_segments = 512\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"max_connections = 100\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"wal_level = replica\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"archive_mode = ${archive_mode}\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"archive_command = '/bin/cp -f %p ${install_dir}/archive/%f'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"control_file_copy = '${install_dir}/copy_file'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"max_replication_slots = 32\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"hot_standby = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"hot_standby_feedback = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"logging_collector = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"log_destination = 'csvlog'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"log_checkpoints = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"log_replication_commands = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"wal_compression = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"synchronous_commit = remote_apply\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"max_prepared_transactions = 100\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"shared_buffers = 512MB\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"fsync = on\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"timezone = 'PRC'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"lc_messages = 'C'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"lc_monetary = 'C'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"lc_numeric = 'C'\" >> ${data_directory}/es_rep.conf"
    execute_command ${execute_user} ${primary_host} "echo \"lc_time = 'C'\" >> ${data_directory}/es_rep.conf"

    if [ -n "${tcp_keepalives_idle}" ]; then
		execute_command ${execute_user} ${primary_host} "echo \"tcp_keepalives_idle = ${tcp_keepalives_idle}\" >> ${data_directory}/es_rep.conf"
	fi

	if [ -n "${tcp_keepalives_interval}" ]; then
		execute_command ${execute_user} ${primary_host} "echo \"tcp_keepalives_interval = ${tcp_keepalives_interval}\" >> ${data_directory}/es_rep.conf"
	fi

	if [ -n "${tcp_keepalives_count}" ]; then
		execute_command ${execute_user} ${primary_host} "echo \"tcp_keepalives_count = ${tcp_keepalives_count}\" >> ${data_directory}/es_rep.conf"
	fi

    if [ -n "${tcp_user_timeout}" ]; then
	    execute_command ${execute_user} ${primary_host} "echo \"tcp_user_timeout = ${tcp_user_timeout}\" >> ${data_directory}/es_rep.conf"
    fi

    if [ -n "$wal_sender_timeout" ]; then
        execute_command ${execute_user} ${primary_host} "echo \"wal_sender_timeout = ${wal_sender_timeout}\" >> ${data_directory}/es_rep.conf"
    fi
   
    if [ -n "${wal_receiver_timeout}" ]; then
        execute_command ${execute_user} ${primary_host} "echo \"wal_receiver_timeout = ${wal_receiver_timeout}\" >> ${data_directory}/es_rep.conf"
    fi

    echo "[INSTALL] wirte the es_rep.conf on \"${primary_host}\" ... OK"

    # config the database identity authentication file sys_hba.conf
    echo "[INSTALL] wirte the sys_hba.conf on \"${primary_host}\" ..."
    if [ $on_bmj -eq 0 ]
    then
        execute_command ${execute_user} ${primary_host} "sed -i -e \"s/\(.*0\.0\.0\.0\/0\(.*\)$\)/#\1/g\" ${data_directory}/sys_hba.conf"
    else
        execute_command ${execute_user} ${primary_host} "sed -e \"s/\(.*0\.0\.0\.0\/0\(.*\)$\)/#\1/g\" ${data_directory}/sys_hba.conf > ${data_directory}/sys_hba.conf.tmp && cat ${data_directory}/sys_hba.conf.tmp > ${data_directory}/sys_hba.conf && /bin/rm -rf ${data_directory}/sys_hba.conf.tmp"
    fi

    execute_command ${execute_user} ${primary_host} "echo \"host    all             all             0.0.0.0/0               ${db_auth}\" >> ${data_directory}/sys_hba.conf"
    execute_command ${execute_user} ${primary_host} "echo \"host    replication     all             0.0.0.0/0               ${db_auth}\" >> ${data_directory}/sys_hba.conf"
    execute_command ${execute_user} ${primary_host} "echo \"host    replication     all             ::0/0                   ${db_auth}\" >> ${data_directory}/sys_hba.conf"

    echo "[INSTALL] wirte the sys_hba.conf on \"${primary_host}\" ... OK"

    # config secret-free configuration file .encpwd
    esrep_passwd="S2luZ2Jhc2VoYTExMA=="
    esrep_passwd_base64=`echo "${esrep_passwd}" | base64 -d`
    echo "[INSTALL] wirte the .encpwd on every host"
    for ip in ${all_ip[@]}
    do
        execute_command ${execute_user} $ip "${sys_bindir}/sys_encpwd -H \* -P \* -D \* -U ${db_user} -W '${db_password}'"
        execute_command ${execute_user} $ip "${sys_bindir}/sys_encpwd -H \* -P \* -D \* -U esrep -W '${esrep_passwd_base64}'"
    done

    # config repmgr.conf
    local id_count=1
    local i=0
    local cur_location=""
    echo "[INSTALL] write the repmgr.conf on every host"
    for ip in ${all_ip[@]}
    do
        local node_conninfo=""
        node_conninfo="host=$ip ${conninfo} connect_timeout=${connection_timeout}"

		if [ -n "${tcp_keepalives_idle}" ]; then
			node_conninfo="${node_conninfo} keepalives=1 keepalives_idle=${tcp_keepalives_idle}"
		fi

		if [ -n "${tcp_keepalives_interval}" ]; then
			node_conninfo="${node_conninfo} keepalives_interval=${tcp_keepalives_interval}"
		fi

		if [ -n "${tcp_keepalives_count}" ]; then
			node_conninfo="${node_conninfo} keepalives_count=${tcp_keepalives_count}"
		fi

		if [ -n "${tcp_user_timeout}" ]; then
			node_conninfo="${node_conninfo} tcp_user_timeout=${tcp_user_timeout}"
		fi


        echo "[INSTALL] write the repmgr.conf on \"${ip}\" ..."

        if [ $use_scmd -eq 1 ]
        then
            execute_command ${execute_user} $ip "echo \"use_scmd=on\" > ${install_dir}/etc/repmgr.conf"
        else
            execute_command ${execute_user} $ip "echo \"use_scmd=off\" > ${install_dir}/etc/repmgr.conf"
        fi
        execute_command ${execute_user} $ip "echo \"ha_running_mode='${ha_running_mode}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"node_id=$id_count\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"node_name='node${id_count}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"conninfo='${node_conninfo}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"connection_check_type='mix'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"data_directory='${data_directory}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"log_file='${log_file}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"kbha_log_file='${kbha_log_file}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"sys_bindir='${sys_bindir}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"scmd_options='${scmd_options}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"trusted_servers='${trusted_servers}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"running_under_failure_trusted_servers='${running_under_failure_trusted_servers}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"repmgrd_pid_file='${repmgrd_pid_file}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"kbha_pid_file='${kbha_pid_file}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"\" >> ${install_dir}/etc/repmgr.conf"
        if [ "${ha_running_mode}"x = "TPTC"x ]
        then
            if [ "$ip"x = "${production_ip[0]}"x ]
            then
               cur_location="production"
            elif [ "$ip"x = "${local_disaster_recovery_ip[0]}"x ]
            then
                cur_location="local_disaster"
            elif [ "$ip"x = "${remote_disaster_recovery_ip[0]}"x ]
            then
                cur_location="remote_disaster"
            fi
            execute_command ${execute_user} $ip "echo \"location='${cur_location}'\" >> ${install_dir}/etc/repmgr.conf"
            if [ "${cur_location}"x = "remote_disaster"x ]
            then
                execute_command ${execute_user} $ip "echo \"failover='manual'\" >> ${install_dir}/etc/repmgr.conf"
            else
                execute_command ${execute_user} $ip "echo \"failover='automatic'\" >> ${install_dir}/etc/repmgr.conf"
            fi
            execute_command ${execute_user} $ip "echo \"failover_need_server_alive='${failover_need_server_alive}'\" >> ${install_dir}/etc/repmgr.conf"
            execute_command ${execute_user} $ip "echo \"sync_in_same_location='${sync_in_same_location}'\" >> ${install_dir}/etc/repmgr.conf"
        else
            execute_command ${execute_user} $ip "echo \"failover='automatic'\" >> ${install_dir}/etc/repmgr.conf"
        fi
        execute_command ${execute_user} $ip "echo \"synchronous='${synchronous}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"recovery='${recovery}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"auto_cluster_recovery_level='${auto_cluster_recovery_level}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"monitoring_history='no'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"reconnect_attempts=${reconnect_attempts}\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"reconnect_interval=${reconnect_interval}\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"promote_command='${sys_bindir}/repmgr standby promote -f ${install_dir}/etc/repmgr.conf'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"follow_command='${sys_bindir}/repmgr standby follow -f ${install_dir}/etc/repmgr.conf -W --upstream-node-id=%n'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"ping_path='${ping_path}'\" >> ${install_dir}/etc/repmgr.conf"
        execute_command ${execute_user} $ip "echo \"use_check_disk='${use_check_disk}'\" >> ${install_dir}/etc/repmgr.conf"

        if [ "${virtual_ip}"x != ""x ]
        then
            execute_command ${execute_user} $ip "echo \"virtual_ip='${virtual_ip}'\" >> ${install_dir}/etc/repmgr.conf"
            execute_command ${execute_user} $ip "echo \"ipaddr_path='${ipaddr_path}'\" >> ${install_dir}/etc/repmgr.conf"
            execute_command ${execute_user} $ip "echo \"arping_path='${arping_path}'\" >> ${install_dir}/etc/repmgr.conf"
            if [ "$ip"x != "${witness_ip}"x ]
            then
                if [ $net_num -eq 1 ]
                then
                    execute_command ${execute_user} $ip "echo \"net_device='${net_device}'\" >> ${install_dir}/etc/repmgr.conf"
                else
                    execute_command ${execute_user} $ip "echo \"net_device='${net_device[$i]}'\" >> ${install_dir}/etc/repmgr.conf"
                fi

                execute_command ${execute_user} $ip "echo \"net_device_ip='${net_device_ip[$i]}'\" >> ${install_dir}/etc/repmgr.conf"
            else
                execute_command ${execute_user} $ip "echo \"net_device='null'\" >> ${install_dir}/etc/repmgr.conf"
                execute_command ${execute_user} $ip "echo \"net_device_ip='null'\" >> ${install_dir}/etc/repmgr.conf"
            fi
        fi

        if [ "${basebackup_options}"x != ""x ]
        then
            execute_command ${execute_user} $ip "echo \"sys_basebackup_options='${basebackup_options}'\" >> ${install_dir}/etc/repmgr.conf"
        fi

        echo "[INSTALL] write the repmgr.conf on \"${ip}\" ... OK"
        let id_count++
        let i++
    done

    # config all_nodes_tools.conf file
    db_base64_pass=`echo "$db_password" | base64 -w 0`
    for ip in ${all_ip[@]}
    do
        execute_command ${execute_user} $ip "echo \"db_u=$db_user\" > ${install_dir}/etc/all_nodes_tools.conf"
        execute_command ${execute_user} $ip "echo \"db_password=$db_base64_pass\" >> ${install_dir}/etc/all_nodes_tools.conf"
        execute_command ${execute_user} $ip "echo \"db_port=$db_port\" >> ${install_dir}/etc/all_nodes_tools.conf"
        execute_command ${execute_user} $ip "echo \"db_name=test\" >> ${install_dir}/etc/all_nodes_tools.conf"
    done

    # start up the primary database
    echo "[INSTALL] start up the database on \"${primary_host}\" ..."
    echo "[INSTALL] ${sys_bindir}/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start"
    execute_command ${execute_user} ${primary_host} "${sys_bindir}/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] start up the database on \"${primary_host}\" ... OK"

    # create the database and user used by repmgr, and regitser the primary node
    echo "[INSTALL] create the database \"esrep\" and user \"esrep\" for repmgr ..."
    execute_command ${execute_user} ${primary_host} "${sys_bindir}/ksql -d test -U ${db_user} -p ${db_port} -c \"create database esrep;\""
    execute_command ${execute_user} ${primary_host} "${sys_bindir}/ksql -d test -U ${db_user} -p ${db_port} -c \"create user esrep with superuser password '${esrep_passwd_base64}';\""
    echo "[INSTALL] create the database \"esrep\" and user \"esrep\" for repmgr ... OK"
    echo "[INSTALL] register the primary on \"${primary_host}\" ..."
    execute_command ${execute_user} ${primary_host} "${sys_bindir}/repmgr primary register"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] register the primary on \"${primary_host}\" ... OK"

    # clone slave host
    echo "[INSTALL] clone and start up the standby ..."
    local upstream_host="${primary_host}"
    local id_index=0
    local upstream_id=1
    for ip in ${all_ip[@]}
    do
        let id_index++
        [ "$ip"x = "${primary_host}"x ] && continue
        [ "$ip"x = "${witness_ip}"x ] && continue
        echo "clone the standby on \"${ip}\" ..."
        echo "${sys_bindir}/repmgr -h ${upstream_host} -U esrep -d esrep -p ${db_port} --upstream-node-id ${upstream_id} standby clone"
        execute_command ${execute_user} ${ip} "${sys_bindir}/repmgr -h ${upstream_host} -U esrep -d esrep -p ${db_port} --upstream-node-id ${upstream_id} standby clone"
        [ $? -ne 0 ] && exit 1
        echo "clone the standby on \"${ip}\" ... OK"
        echo "start up the standby on \"${ip}\" ..."
        echo "${sys_bindir}/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start"
        execute_command ${execute_user} ${ip} "${sys_bindir}/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start"
        [ $? -ne 0 ] && exit 1
        echo "start up the standby on \"${ip}\" ... OK"
        echo "register the standby on \"${ip}\" ..."
        execute_command ${execute_user} ${ip} "${sys_bindir}/repmgr --upstream-node-id ${upstream_id} standby register"
        [ $? -ne 0 ] && exit 1
        echo "[INSTALL] register the standby on \"${ip}\" ... OK"

        if [ "${ha_running_mode}"x = "TPTC"x ]
        then
            # the first node follows the last upsteam node, other nodes follow the first node.
            if [ "$ip"x = "${local_disaster_recovery_ip[0]}"x -o "$ip"x = "${remote_disaster_recovery_ip[0]}"x ]
            then
                upstream_host="${ip}"
                upstream_id="${id_index}"
            fi
        fi
    done

	if [ "${witness_ip}"x != ""x ]
    then
        echo "[INSTALL] now create witness node"
        create_witness_node
    fi

    # start up the cluster
    echo "[INSTALL] start up the whole cluster ..."
    execute_command ${execute_user} ${primary_host} "${sys_bindir}/sys_monitor.sh start"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] start up the whole cluster ... OK"
}
function load_config_from_cluster()
{
    echo  "[INSTALL] load config from cluster....."

    local cluster_db_user=`read_conf_value "$primary_ip" "${node_tools_conf}" "db_u"`
    compare_param_diff "db_user" "$db_user" "$cluster_db_user"
    db_user=$cluster_db_user
    echo " [INFO] db_user=${cluster_db_user}"

    set_param_from_cluster_conf  "$node_tools_conf" "db_port" "$db_port"

    # parameter only expand need
    if [ "$function_name"x == "expand"x ]
    then
        set_param_from_cluster_conf  "$repmgr_conf"  "data_directory"  "$data_directory"
        # expandtype is witness,then need read db_mode db_auth db_case_sentive
        if [ "$expand_type"x == "1"x ]
        then
            local cluster_db_mode=`execute_command ${execute_user} ${primary_ip} "${sys_bindir}/ksql -U esrep -p ${db_port} -d test -Atqc \"show database_mode;\""`
            [ $? -ne 0 -o "$cluster_db_mode"x == ""x ] && exit 1
            db_mode=${cluster_db_mode}
            echo " [INFO] db_mode=${cluster_db_mode}"

            local cluster_db_auth=`execute_command ${execute_user} ${primary_ip} "cat ${data_directory}/sys_hba.conf|tail -n 1 | awk '{ print \\$5 }' "`
            compare_param_diff "db_auth" "$db_auth" "$cluster_db_auth"
            db_auth=$cluster_db_auth
            echo " [INFO] db_auth=${db_auth}"

            local cluster_db_case_sentive=`execute_command ${execute_user} ${primary_ip} "${sys_bindir}/ksql -d test -U esrep -p ${db_port} -Atqc \"show enable_ci;\""`
            compare_param_diff "db_case_sentive" "$db_case_sentive" "$cluster_db_case_sentive"
            db_case_sentive=$cluster_db_case_sentive
            echo " [INFO] db_case_sentive=${db_case_sentive}"
        fi

        local cluster_scmd_port=`execute_command ${super_user} ${primary_ip} "test -f ${scmd_conf} && cat ${scmd_conf} |grep -w ^Port|awk  '{ print \\$2 }'"`
        if [ "$cluster_scmd_port"x != ""x ]
        then
            compare_param_diff "scmd_port" "$scmd_port" "$cluster_scmd_port"
            scmd_port=$cluster_scmd_port
            echo " [INFO] scmd_port=${scmd_port}"
        fi

        set_param_from_cluster_conf  "$repmgr_conf"  "recovery" "$recovery"

        set_param_from_cluster_conf  "$repmgr_conf"  "auto_cluster_recovery_level"  "$auto_cluster_recovery_level"

        set_param_from_cluster_conf  "$repmgr_conf"  "use_check_disk" "$use_check_disk"

        set_param_from_cluster_conf  "$repmgr_conf" "trusted_servers" "$trusted_servers"

        local cluster_virtual_ip=`read_conf_value "$primary_ip" "${repmgr_conf}" "virtual_ip"`
        if [ "$virtual_ip"x != "$cluster_virtual_ip"x ]
        then
            echo "[WARNING] the ${install_conf} param[virtual_ip]:$virtual_ip is not same with cluster param[virtual_ip]:$cluster_virtual_ip"
        fi

        eval virtual_ip="$cluster_virtual_ip"

        if [ "$virtual_ip"x != ""x ]
        then
            echo " [INFO] virtual_ip=${virtual_ip}"

            set_param_from_cluster_conf  "$repmgr_conf"  "ipaddr_path"  "$ipaddr_path"

            set_param_from_cluster_conf  "$repmgr_conf"  "ping_path"  "$ping_path"

            set_param_from_cluster_conf  "$repmgr_conf"  "arping_path"  "$arping_path"
        fi
        set_param_from_cluster_conf  "$repmgr_conf"  "reconnect_attempts" "$reconnect_attempts"

        set_param_from_cluster_conf  "$repmgr_conf"  "reconnect_interval"  "$reconnect_interval"
    fi

    local repmgr_use_scmd=`read_conf_value "$primary_ip" ${repmgr_conf} use_scmd`
    if [ "$repmgr_use_scmd"x == "on"x ]
    then
        compare_param_diff "use_scmd" "$use_scmd" "1"
        use_scmd=1
    else
        compare_param_diff "use_scmd" "$use_scmd" "0"
        use_scmd=0
    fi
    echo " [INFO] use_scmd=${use_scmd}"

    # forbid Three centers in two places
    local cluster_ha_running_mode=`read_conf_value "$primary_ip" "$repmgr_conf" "ha_running_mode"`
    if [ "$cluster_ha_running_mode"x == "TPTC"x ]
    then
        echo "[ERROR] the $repmgr_conf param[ha_running_mode] is $cluster_ha_running_mode, expand and shrink do not support TPTC! exit!"
        exit 1
    fi

    echo  "[INSTALL] load config from cluster.....OK"
}

function load_conf_value_under_header()
{
    local conf_path=$1
    local target_header=\[$2\]
    local read_flag=0
    if [ -f $conf_path ]
    then
        while read t_one_line ;
        do
            local is_header=`echo "$t_one_line" |  egrep '^\[.*]' | wc -l`
            if [ $is_header -eq 1 ]
            then
                if [ x"$target_header" == x"$t_one_line" ]
                then
                    read_flag=1
                else
                    read_flag=0
                fi
           fi
           if [ $read_flag -eq 1 -a $is_header -eq 0 ]
           then
               eval ${t_one_line} ;
           fi
        done < $conf_path
    fi
}

function read_conf_value()
{
    local ip=$1
    local conf_path=$2
    local conf_key=$3
    execute_command ${super_user} ${ip} "test -f $conf_path"
    [ $? -ne 0 ] && return 1
    local value=`execute_command ${super_user} ${ip} "cat $conf_path |grep -aEw \"$conf_key\" |tail -n 1|awk -F '=' '{print \\$2}' | tr -d [\\'] "`
    echo $value
}
function read_conf_value_local()
{
    local conf_path=$1
    local conf_key=$2
    test -f "$conf_path"
    [ $? -ne 0 ] && exit 1
    cat $conf_path |grep -aEw "$conf_key" |tail -n 1|awk -F '=' '{print $2}' | tr -d [\']
    echo $value
}
function read_conf_value_under_header()
{
  local conf_path=$1
  local conf_header=$2
  local conf_key=$3
  local conf_value=`awk -F '=' '/\['$conf_header'\]/{a=1}a==1&&$1~/'$conf_key'/{print $2;exit}'  "$conf_path"`
  if [ $? -ne 0 ]
  then
      echo "[`date`] [Error] read_conf_value_under_header conf_header:$conf_header key:$conf_key from conf_path:$conf_path fail! conf_value:$conf_value"
      exit 1
  fi
  echo $conf_value
}


function set_binary()
{
    if [ "$use_scmd"x == "1"x ]
    then
        binary_remote="${sys_bindir}/sys_securecmd"
        scmd_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${scmd_port}"
    else
        binary_remote="ssh"
        scmd_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${ssh_port}"
    fi

    if [ -n "${tcp_keepalives_interval}" ]; then
        scmd_options="${scmd_options} -o ServerAliveInterval=${tcp_keepalives_interval}"
    fi

    if [ -n "${tcp_keepalives_count}" ]; then
	    scmd_options="${scmd_options} -o ServerAliveCountMax=${tcp_keepalives_count}"
    fi

    # used by execute_command
    if [ "$deploy_by_sshd"x == "1"x ]
    then
        binary_local="ssh"
        command_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${ssh_port}"
    else
        binary_local="${sys_bindir}/sys_securecmd"
        command_options="-q -o ConnectTimeout=$connection_timeout -o StrictHostKeyChecking=no -p ${scmd_port}"
    fi

    if [ -n "${tcp_keepalives_interval}" ]; then
        command_options="${command_options} -o ServerAliveInterval=${tcp_keepalives_interval}"
    fi

    if [ -n "${tcp_keepalives_count}" ]; then
	    command_options="${command_options} -o ServerAliveCountMax=${tcp_keepalives_count}"
    fi
}

function check_net()
{
    local ip1=$1
    local ip2=$2
    local should_exit=0

    [ "$binary_remote"x == ""x -o "$binary_local"x == ""x -o "${command_options}"x == ""x -o "${scmd_options}"x == ""x ] && set_binary
    test_connect "$ip1" "$ip2"
    for ip in {$ip1,$ip2}
    do
        test_ssh $ip
        if [ $? -ne 0 ]
        then
            if [ "$binary_remote"x == "${sys_bindir}/sys_securecmd"x ]
            then
                echo "[RUNNING] can not connect to \"${ip1}\", please check your configuration.scmd_port:${scmd_port} super_user:${super_user} execute_user:${execute_user}"
            elif [ "$binary_remote"x == "ssh"x ]
            then
                echo "[RUNNING] can not connect to \"${ip1}\", please check your configuration.ssh_port:${ssh_port} super_user:${super_user} execute_user:${execute_user}"
            fi
            break
        else
            echo "[RUNNING] success connect to the target \"${ip1}\" ..... OK"
        fi
    done

    test_connect $ip1
    if [ $? -ne 0 ]
    then
        if [ "$binary_remote"x == "${sys_bindir}/sys_securecmd"x ]
        then
            echo "[RUNNING] can not connect to $ip1 from current node by '${binary_remote}',scmd_port:${scmd_port} super_user:${super_user} execute_user:${execute_user}"
        elif [ "$binary_remote"x == "ssh"x ]
        then
            echo "[RUNNING] can not connect to $ip1 from current node by '${binary_remote}',ssh_port:${ssh_port} super_user:${super_user} execute_user:${execute_user}"
        fi
        should_exit=1
    else
        echo "[RUNNING] success connect to \"${ip1}\" from current node by '${binary_local}' ..... OK"
    fi

    test_connect $ip1 $ip2
    if [ $? -ne 0 ]
    then
        if [ "$binary_remote"x == "${sys_bindir}/sys_securecmd"x ]
        then
                echo "[RUNNING] can not connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}',scmd_port:${scmd_port} super_user:${super_user} execute_user:${execute_user}"
        elif [ "$binary_remote"x == "ssh"x ]
        then
                echo "[RUNNING] can not connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}',ssh_port:${ssh_port} super_user:${super_user} execute_user:${execute_user}"
        fi
        should_exit=1
    else
        echo "[RUNNING] success connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}' ..... OK"
    fi
    [ $should_exit -eq 1 ] && exit 1
}
function check_script_node_position_local()
{
    if [ "$function_name"x = "expand"x ]
    then
        echo "[CONFIG_CHECK] The localhost is expand_ip:[${expand_ip}] ..."
        local ip_count=`ip address | grep -w "${expand_ip}" | wc -l`
        if [ $? -ne 0 ] || [ ${ip_count} -eq 0 ]
        then
            echo "[CONFIG_CHECK] localhost is not expand_ip:[${expand_ip}],ip_count:$ip_count,exit 1"
            exit 1
        fi
        echo "[CONFIG_CHECK] The localhost is expand_ip:[${expand_ip}] ...ok"
    elif [ "$function_name"x == "shrink"x ]
    then
        echo "[CONFIG_CHECK] localhost is shrink_ip:[${shrink_ip}]/primary_ip:[${primary_ip}]..."
        local conninto=`cat "${repmgr_conf}" |grep -aEw "conninfo" |tail -n 1`
        local cur_host=`echo $conninto | awk -F "'" '{print $2}' | awk -F " " '{for(i=1;i<=NF;i++){print $i}}'|grep "host=" |tail -n 1|awk -F "=" '{print $2}'`
        if [ "$primary_ip"x != "$cur_host"x ] && [ "${shrink_ip}"x != "$cur_host"x ]
        then
            echo "[CONFIG_CHECK] localhost:${cur_host} in ${repmgr_conf}  is not shrink_ip:[${shrink_ip}]/primary_ip:[${primary_ip}],exit 1"
            exit 1
        fi
        echo "[CONFIG_CHECK] localhost is shrink_ip:[${shrink_ip}]/primary_ip:[${primary_ip}]...ok"
    fi
}
function check_data_dir()
{
    local ip=$1
    if [ "$use_scmd"x == "1"x ]
    then
        echo "[RUNNING] the data dir \"${data_directory}\" exist on \"${ip}\" ...."
        execute_command ${execute_user} $ip "test ! -e ${data_directory}"
        [ $? -ne 0 ] && exit 1
        echo "[RUNNING] the data dir \"${data_directory}\" exist on \"${ip}\" ....OK"
    fi
}
function check_install_dir()
{
    local ip=$1
    local should_exit=0

    execute_command ${execute_user} $ip "test ! -e ${install_dir}"
    if [ $? -ne 0 ]
    then
        if [ $on_bmj -eq 0 ]
        then
            if [ $deploy_by_sshd -eq 1 ]
            then
                should_exit=1
                echo "[ERROR] the install dir \"${install_dir}\" on \"${ip}\" is already exist, please remove it first."
            else
                echo "[RUNNING] when deploy_by_sshd=0, the install dir \"${install_dir}\" on \"${ip}\" is right .... OK"
            fi
        else
            echo "[RUNNING] the install dir \"${install_dir}\" on \"${ip}\" of BMJ is right .... OK"
        fi
    else
        if [ $on_bmj -eq 0 ]
        then
            if [ $deploy_by_sshd -eq 1 ]
            then
                echo "[RUNNING] the install dir is not exist on \"${ip}\" ..... OK"
            else
                should_exit=1
                echo "[ERROR] when deploy_by_sshd=0, there have not installed kingbase databse on \"${ip}\" yet ..... failed"
            fi
        else
            should_exit=1
            echo "[ERROR] there have not installed kingbase databse on \"${ip}\" of BMJ yet ..... failed"
        fi
    fi
    [ $should_exit -eq 1 ]&&exit 1
}
function check_deploy_by_sshd()
{
    # check values for deploy_by_sshd and use_scmd
    if [ $on_bmj -eq 1 ]
    then
        deploy_by_sshd=0
        use_scmd=1
    else
        if [ ${deploy_by_sshd} -ne 0 -a ${deploy_by_sshd} -ne 1 ]
        then
            echo "[WARNING] invalid value ${deploy_by_sshd} for deploy_by_sshd, set it to 1 as default."
            deploy_by_sshd=1
        fi
        if [ ${use_scmd} -ne 0 -a ${use_scmd} -ne 1 ]
        then
            echo "[WARNING] invalid value ${use_scmd} for use_scmd, set it to 1 as default."
            use_scmd=1
        fi
        if [ ${deploy_by_sshd} -eq 0 -a ${use_scmd} -eq 0 ]
        then
            echo "[CONFIG_CHECK] param [deploy_by_sshd] and [use_scmd] could not be both 0"
            return 1
        fi
    fi
}
function check_securecmdd()
{
    local ip=$1
    local should_exit=0
    if [ $deploy_by_sshd -eq 1 -a $use_scmd -eq 1 ]
    then
        # check if there is sys_securecmdd running on the host
        echo "[RUNNING] check the sys_securecmdd is running or not..."
        es_running=`execute_command ${super_user} $ip "netstat -apn 2>/dev/null|grep -w \"${scmd_port}\"|wc -l"`
        if [ $? -ne 0 -o "${es_running}"x != "0"x ]
        then
            should_exit=1
            echo "[ERROR] the sys_securecmdd on \"${ip}:${scmd_port}\" is running, please stop it first."
        else
            echo "[RUNNING] the sys_securecmdd is not running on \"${ip}:${scmd_port}\" ..... OK"
        fi
        [ $should_exit -eq 1 ] && exit 1
    elif [ $deploy_by_sshd -eq 0 -a $on_bmj -eq 0 ]
    then
        # check if there is ~/.es for execute_user
        echo "[RUNNING] check the ~/.es for ${execute_user} ..."
        local es_home_path="/home/${execute_user}/.es"
        execute_command ${super_user} $ip "test -d ${es_home_path} && chown -R ${execute_user}:${execute_user} ${es_home_path}"
        if [ $? -ne 0 ]
        then
            execute_command ${super_user} $ip "cp -rf /root/.es ${es_home_path} && chown -R ${execute_user}:${execute_user} ${es_home_path}"
            if [ $? -ne 0 ]
            then
                should_exit=1
                echo "[ERROR] failed to copy /root/.es to ${es_home_path} on \"${ip}\"."
            else
                echo "[RUNNING] copy /root/.es to ${es_home_path} on \"${ip}\" ..... OK"
            fi
        else
            echo "[RUNNING] the ${es_home_path} is already exists on \"${ip}\" ..... OK"
        fi
        [ $should_exit -eq 1 ] && exit 1
    fi
}
function start_securecmdd()
{
    local ip=$1
    local should_exit=0
    # config sys_securecmdd and start it
    if [ $deploy_by_sshd -eq 1 -a $use_scmd -eq 1 ]
    then
        echo "[RUNNING] config sys_securecmdd and start it ..."
        echo "[RUNNING] config the sys_securecmdd port to ${scmd_port} ..."
        execute_command ${execute_user} $ip "sed -i \"/^scmd_port[ ]*=/cscmd_port=${scmd_port}\" ${sys_bindir}/../share/sys_HAscmdd.conf"
        if [ $? -ne 0 ]
        then
            echo "[ERROR] config the sys_securecmdd port failed on $ip"
            exit 1
        else
            echo "[RUNNING] success to config the sys_securecmdd port on $ip ... OK"
        fi
        execute_command ${super_user} $ip "${sys_bindir}/sys_HAscmdd.sh init"
        if [ $? -ne 0 ]
        then
            echo "[ERROR] config sys_securecmdd failed on $ip"
            exit 1
        else
            echo "[RUNNING] success to config sys_securecmdd on $ip ... OK"
        fi

        execute_command ${super_user} $ip "${sys_bindir}/sys_HAscmdd.sh start"
        if [ $? -ne 0 ]
        then
            echo "[ERROR] start sys_securecmdd failed on $ip"
            exit 1
        else
            echo "[RUNNING] success to start sys_securecmdd on $ip ... OK"
        fi
    fi
}
function shrink_pre_check()
{
    local primary_ip=$1
    local shrink_ip=$2

    check_install_conf

    check_script_node_position_local

    check_primary_ip "$primary_ip"

    check_node_id "$primary_ip" "$node_id" "$shrink_ip"

    # check bin dir
    echo "[RUNNING] The ${sys_bindir} dir exist on \"${shrink_ip}\" ... "
    execute_command ${execute_user} $shrink_ip "test -e ${sys_bindir}"
    [ $? -ne 0 ] && exit 1
    echo "[RUNNING] The ${sys_bindir} dir exist on \"${shrink_ip}\" ... OK"

    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show"
    # check shrink node is in cluster
    echo "[RUNNING] Del node exist in cluster ..."
    local is_in_cluster=`execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show" |grep -aEw ${shrink_ip}|wc -l `
    if [ $is_in_cluster -eq 0 ]
    then
        echo "[ERROR] Del node not exist in cluster, check fail"
        exit 1
    fi
    echo "[RUNNING] Del node exist in cluster ... OK"

    # check del node is standby
    if [ $shrink_type -eq 0 ]
    then
        echo "[RUNNING] Del node is standby ..."
        local is_standby=`execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show" | grep standby | grep -w "${shrink_ip}"|wc -l`
        if [ $is_standby -ne 1 ]
        then
            echo "[ERROR] IP:$shrink_ip to deleted is not standby node, check fail"
            exit 1
        fi
        echo "[INFO] node:$shrink_ip can be deleted ... OK"
    elif [ $shrink_type -eq 1 ]
    then
        echo "[RUNNING] Del node is witness ..."
        local is_witness=`execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show" | grep witness | grep -w "${shrink_ip}"|wc -l`
        if [ $is_witness -ne 1 ]
        then
            echo "[ERROR] IP:$shrink_ip to deleted is not witness node, check fail"
            exit 1
        fi
        echo "[INFO] node:$shrink_ip can be deleted ... OK"
    fi
}
function get_and_update_conninfo()
{
    local primary_host=$1
    local expand_ip=$2
    local conninfo=`execute_command ${execute_user} $primary_host "${sys_bindir}/repmgr cluster show  | grep -v \"Connection string\" |grep $primary_host |awk -F \"|\" '{for(i=1;i<=NF;i++){print \\$i}}'|grep "host=" |tail -n 1| awk '\\$1=\\$1'  |sed \"s/host=\([0-9.:a-zA-Z-]*\) /host=${expand_ip} /g\""`
    echo "$conninfo"
}
function set_or_update_parm()
{
    local ip=$1
    local conf_name=$2
    local parameter=$3
    local delimiter=""

    echo " [INFO] parameter_name=`echo $parameter |awk -F "=" '{print $1}'`"
    parameter_name=`echo $parameter |awk -F "=" '{print $1}'`

    echo " [INFO] parameter_values=`echo $parameter |awk -F "=" '{print $2}'`"
    parameter_values=`echo $parameter |awk -F "=" '{print $2}'`


    if [ "$parameter_name"x != ""x -a "$parameter_values"x != ""x -a "$parameter_values"x != "''"x ]
    then
        delimiter="="
    elif [ "$parameter_values"x = ""x ] && [ "`echo $parameter | grep = | wc -l`"x = "0"x  ]
    then
        local value1=""
        local value2=""

        value1=execute_command ${execute_user} ${ip} "echo $parameter | awk -F " " '{print \\$1}' 2>/dev/null"
        value2=execute_command ${execute_user} ${ip} "echo $parameter | awk -F " " '{print \\$2}' 2>/dev/null"
        if [ "$value1"x != ""x -a "$value2"x != ""x -a "$value2"x != "''"x ]
        then
            echo " [INFO] parameter_name=${value1}"
            parameter_name="${value1}"
            echo " [INFO] parameter_values=${value2}"
            parameter_values="${value2}"
            delimiter="[ ]"
        fi
    fi

    if [ "${delimiter}"x != ""x ]
    then
        para_exist=`execute_command ${execute_user} ${ip} "grep -wRn $parameter_name $conf_name |wc -l"`
        echo " [INFO] [parameter_name] para_exist=$para_exist"

        if [ $para_exist -eq 0 ]
        then
            echo " [INFO] \"$parameter\" >> $conf_name"
            execute_command ${execute_user} ${ip} "echo \"$parameter\" >> $conf_name"
        else
            if [ $on_bmj -eq 0 ]
            then
                echo " [INFO] sed -i \"/[#]*${parameter_name}[ ]*${delimiter}/c${parameter}\" $conf_name"
                execute_command ${execute_user} ${ip} "sed -i \"/^[# ]*${parameter_name}[ ]*${delimiter}/c${parameter}\" $conf_name"
            else
                echo " [INFO] sed \"/[#]*${parameter_name}[ ]*${delimiter}/c${parameter}\" $conf_name > $shell_folder/conf.temp"

                execute_command ${execute_user} ${ip} "sed \"/^[# ]*${parameter_name}[ ]*${delimiter}/c${parameter}\" $conf_name > $shell_folder/conf.temp"
                echo " [INFO] cat $shell_folder/conf.temp > $conf_name"

                execute_command ${execute_user} ${ip} "cat $shell_folder/conf.temp > $conf_name"

                execute_command ${execute_user} ${ip} "/bin/rm -f $shell_folder/conf.temp 2>/dev/null"
            fi
        fi
    fi
}
check_and_change_arping()
{
    local ip=$1
    # if VIP is set, change the auth of ip、arping
    if [ "${virtual_ip}"x != ""x  -a $on_bmj -eq 0 ]
    then
        echo "[RUNNING] chmod u+s for \"${ipaddr_path}\" and \"${arping_path}\" on $ip"
        execute_command ${super_user} $ip "chmod u+s ${ipaddr_path}/ip"
        if [ $? -ne 0 ]
        then
            should_exit=1
            echo "[RUNNING] can not execute \"chmod u+s ${ipaddr_path}/ip\" on \"${ip}\"."
            break
        else
            echo "[RUNNING] chmod u+s ${ipaddr_path}/ip on \"${ip}\" ..... OK"
        fi

        execute_command ${super_user} $ip "chown -R ${super_user}:${super_user} ${arping_path}/arping"
        execute_command ${super_user} $ip "chmod u+s ${arping_path}/arping"
        if [ $? -ne 0 ]
        then
            should_exit=1
            echo "[RUNNING] can not execute \"chmod u+s ${arping_path}/arping\" on \"${ip}\"."
        else
            echo "[RUNNING] chmod u+s ${arping_path}/arping on \"${ip}\" ..... OK"
        fi
        [ $should_exit -eq 1 ] && exit 1
    fi
}
function check_and_cp_license()
{
    local ip=$1
    # check license path
    local num=0
    if [ $deploy_by_sshd -eq 1 ]
    then
        local scp_ret=0
        local ln_ret=0
        scp_ret=0
        ln_ret=0
        #copy license.dat to install_dir
        echo "[INSTALL] check license_file \"${license_file}\""
        if [ -f ${license_path}/${license_file} ]
        then
            if [ $? -ne 0 ]
            then
                echo "[INSTALL] Cannot access license_file: ${license_path}/${license_file}"
                exit 1
            else
                echo "[INSTALL] success to access license_file: ${license_path}/${license_file}"
            fi
        fi
        echo "[INSTALL] Scp license to ${install_dir}/../${license_file} on $ip"
        scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r ${license_path}/${license_file} ${execute_user}@${ip}:${install_dir}/../
        scp_ret=$?
        if [ ${license_file} != "license.dat" ]
        then
            execute_command ${execute_user} $ip "ln -s ${install_dir}/../${license_file} ${sys_bindir}/../../license.dat"
            ln_ret=$?
        fi
        if [ $scp_ret -ne 0 -o $ln_ret -ne 0 ]
        then
            echo "[INSTALL] failed to copy ${license_path}/${license_file} to $install_dir/../ on $ip"
            exit 1
        else
            echo "[INSTALL] success to copy ${license_path}/${license_file} to $install_dir/../ on $ip"
        fi
    elif [ $on_bmj -eq 1 ]
    then
        execute_command ${execute_user} $ip "test -f $license_path"
        if [ $? -eq 0 ]
        then
            echo "[INSTALL] check license_file \"${license_path}\" on $ip .... ok"
        else
            echo "[INSTALL] check license_file \"${license_path}\" on $ip .... failed"
            exit 1
        fi
    else
        execute_command ${execute_user} ${ip} "test ! -f ${sys_bindir}/license.dat && test ! -f ${sys_bindir}/../../license.dat"
        if [ $? -eq 1 ]
        then
            echo "[INSTALL] check license_file \"${sys_bindir}/license.dat\" or \"${sys_bindir}/../../license.dat\" on $ip .... ok"
        else
            echo "[INSTALL] check license_file \"${sys_bindir}/license.dat\" or \"${sys_bindir}/../../license.dat\" on $ip .... failed"
            exit 1
        fi
    fi
}

function check_and_cp_zip()
{
    local ip=$1
    [ $deploy_by_sshd -ne 1 ] && return 0
    if test ! -f ${zip_package}
    then
        if [ $on_bmj -eq 1 ]
        then
            echo "[CONFIG_CHECK] BMJ does not require to set param [zip_package] .... ok"
        elif [ $deploy_by_sshd -eq 0 ]
        then
            echo "[CONFIG_CHECK] when deploy_by_sshd=0, does not require to set param [zip_package] .... ok"
        else
            echo "[CONFIG_CHECK] check the zip file \"${zip_package}\" is not exist"
            exit 1
        fi
    fi

    echo "[INSTALL] create the install dir \"${install_dir}\" on $ip ..."
    execute_command ${execute_user} $ip "mkdir -p ${install_dir}"
    if [ $? -ne 0 ]
    then
        echo "[INSTALL] failed to create the install dir \"${install_dir}\" on \"${ip}\"."
        exit 1
    else
        echo "[INSTALL] success to create the install dir \"${install_dir}\" on \"${ip}\" ..... OK"
    fi
    # cp zip_package to  ${install_dir} of $ip
    echo "[INSTALL] try to copy the zip package \"${zip_package}\" to ${install_dir} of \"${ip}\" ....."
    scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r $zip_package ${execute_user}@${ip}:${install_dir}
    if [ $? -ne 0 ]
    then
        echo "[INSTALL] failed to scp the zip package \"${zip_package}\" ${install_dir} of to \"${ip}\"."
        exit 1
    else
        echo "[INSTALL] success to scp the zip package \"${zip_package}\" ${install_dir} of to \"${ip}\" ..... OK"
    fi

    local zip_file=`basename ${zip_package}`
    [ $? -ne 0 ] && exit 1

    # unzip the zip package to ${install_dir} on $ip
    echo "[INSTALL] decompress the \"${install_dir}\" to \"${install_dir}\" on $ip"
    if [ "$name_zip"x == "1"x ]
    then
        execute_command ${execute_user} ${ip} "unzip -q -o ${install_dir}/${zip_file} -d ${install_dir} 1>/dev/null"
        if [ $? -ne 0 ]
        then
            echo "[INSTALL] failed to decompress the \"${install_dir}/${zip_file}\" to \"${install_dir}\" on \"${ip}\"."
            exit 1
        else
            echo "[INSTALL] success to decompress the \"${install_dir}/${zip_file}\" to \"${install_dir}\" on \"${ip}\"..... OK"
        fi
    elif [ "$name_tar"x == "1"x ]
    then
        execute_command ${execute_user} ${ip} "tar -xvf ${install_dir}/${zip_file} -C ${install_dir} 1>/dev/null"
        if [ $? -ne 0 ]
        then
            echo "[INSTALL] failed to decompress the \"${install_dir}/${zip_file}\" to \"${install_dir}\" on \"${ip}\"."
            exit 1
        else
            echo "[INSTALL] success to decompress the \"${install_dir}/${zip_file}\" to \"${install_dir}\" on \"${ip}\"..... OK"
        fi
    elif [ "$name_gz"x == "1"x ]
    then
        execute_command ${execute_user} ${ip} "tar -zxvf ${install_dir}/${zip_file} -C ${install_dir} 1>/dev/null"
        if [ $? -ne 0 ]
        then
            echo "[INSTALL] failed to decompress the \"${install_dir}/${zip_file}\" to \"${install_dir}\" on \"${ip}\"."
            exit 1
        else

            echo "[INSTALL] success to decompress the \"${install_dir}/${zip_file}\" to \"${install_dir}\" on \"${ip}\"..... OK"
        fi
    fi
    # remove the zip package  on $ip
    execute_command ${execute_user} ${ip} "/bin/rm -rf ${install_dir}/${zip_file}"
    [ $? -ne 0 ] && exit 1
}
function cp_conf()
{
    local src_ip=$1
    local dst_ip=$2
    execute_command ${execute_user} ${dst_ip} "test ! -f $repmgr_conf && mkdir -p ${install_dir}/etc && touch $repmgr_conf"
    execute_command ${execute_user} ${src_ip} "test -f $node_tools_conf"
    if [ $? -ne 0 ]
    then
        echo "[INSTALL] Cannot access file: ${node_tools_conf}"
        exit 1
    else
        echo "[INSTALL] success to access file: ${node_tools_conf}"
    fi
    if [ $deploy_by_sshd -eq 0 ]
    then
        execute_command ${execute_user} ${dst_ip} "$sys_bindir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=${connection_timeout} -l ${execute_user} -T $src_ip \"cat $repmgr_conf \" > $repmgr_conf"
        [ $? -ne 0 ] && exit 1

        echo "[INSTALL] success to copy the \"$repmgr_conf\" from $src_ip to \"${dst_ip}\".....ok"
        execute_command ${execute_user} ${dst_ip} "$sys_bindir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=${connection_timeout} -l ${execute_user} -T $src_ip \"cat ~/.encpwd \" > ~/.encpwd"
        [ $? -ne 0 ] && exit 1

        echo "[INSTALL] success to copy the ~/.encpwd from $src_ip to \"${dst_ip}\"..... ok"
        execute_command ${execute_user} ${dst_ip} "$sys_bindir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=${connection_timeout} -l ${execute_user} -T $src_ip \"cat $node_tools_conf \" > $node_tools_conf"
        [ $? -ne 0 ] && exit 1

        echo "[INSTALL] success to copy ${node_tools_conf} from \"${src_ip}\" to \"${dst_ip}\" ...ok"
    else

        execute_command ${execute_user} ${src_ip} "scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r $repmgr_conf ${execute_user}@${dst_ip}:${install_dir}/etc/"
        [ $? -ne 0 ] && exit 1

        echo "[INSTALL] success to scp the $repmgr_conf from $src_ip to \"${dst_ip}\"..... ok"
        execute_command ${execute_user} ${src_ip} "scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r ~/.encpwd ${execute_user}@${dst_ip}:~/.encpwd"
        [ $? -ne 0 ] && exit 1

        echo "[INSTALL] success to scp the ~/.encpwd from $src_ip to \"${dst_ip}\"..... ok"
        execute_command ${execute_user} ${src_ip} "scp -q -P ${ssh_port} -o StrictHostKeyChecking=no -r ${node_tools_conf} ${execute_user}@${dst_ip}:${node_tools_conf}"
        [ $? -ne 0 ] && exit 1

        echo "[INSTALL] success to scp ${node_tools_conf} from \"${src_ip}\" to \"${dst_ip}\" ...ok"
    fi

    execute_command ${execute_user} ${dst_ip} "chmod 600 ~/.encpwd"
    [ $? -ne 0 ] && exit 1
    echo "[INSTALL] success to chmod 600 the ~/.encpwd on ${dst_ip}..... ok"
}

function change_repmgr_conf()
{
    cp_conf "$primary_ip" "$expand_ip"
    set_or_update_parm "$expand_ip"  "$repmgr_conf" "node_id='$node_id'"
    set_or_update_parm "$expand_ip"  "$repmgr_conf" "node_name='node$node_id'"
    local conninfo=`get_and_update_conninfo $primary_ip $expand_ip`
    set_or_update_parm "$expand_ip"  "$repmgr_conf" "conninfo='$conninfo'"
    set_or_update_parm "$expand_ip"  "$repmgr_conf" "ping_path='$ping_path'"
    if [ "${virtual_ip}"x != ""x ]
    then
        set_or_update_parm $expand_ip  $repmgr_conf "net_device='$net_device'"
        set_or_update_parm $expand_ip  $repmgr_conf "net_device_ip='$net_device_ip'"
        set_or_update_parm "$expand_ip"  "$repmgr_conf" "arping_path='$arping_path'"
        set_or_update_parm "$expand_ip"  "$repmgr_conf" "ipaddr_path='$ipaddr_path'"
    fi
}

function sshstopwitness()
{
    local ip=$1
    echo "[`date`] [INFO] stop witness db ..."
    execute_command ${execute_user} $ip "$sys_bindir/sys_monitor.sh stoplocal 2>/dev/null"
    if [ $? -eq 0 ]
    then
        echo "[`date`] [INFO] stop witness db ...OK"
    fi
}

function sshstopdb()
{
    local primary_ip=$1

    local shrink_ip=$2

    execute_command ${execute_user} $shrink_ip "$sys_bindir/sys_monitor.sh stoplocal 2>/dev/null"

    [ $? -eq 0 ]&&return 0

    local db_exsit=`execute_command ${execute_user} $primary_ip "$sys_bindir/ksql -h $primary_ip -U esrep -d esrep -p $db_port -c \"select * from pg_stat_replication;\" |grep -w \"$shrink_ip\" |wl -c"`

    if [ $db_exsit -eq 0 ]
    then
        echo " [INFO] stop standby db failed,but But the streaming replication connection of db has been disconnected, which does not affect the delete replication slot operation."
    else
        echo " [ERROR] stop standby db failed,the stream replication connection of db still exists, which affects the host to delete the replication slot and exits with an error."
        exit 1
    fi
}
function check_node_id()
{
    local primary_host=$1
    local node_id=$2
    local scale_ip=$3
    local should_exit=0
    echo "[CONFIG_CHECK] check node_id is in cluster ... "
    if [ "$function_name"x == "expand"x ]
    then
        local node_exist=`execute_command ${execute_user} ${primary_host} "${sys_bindir}/ksql -d esrep -h ${primary_host} -U esrep -p ${db_port}  -Atqc \"select count(*) from repmgr.nodes where node_id='$node_id';\""`
        [ "$node_exist"x != "0"x ] && exit 1
    elif [ "$function_name"x == "shrink"x ]
    then
        local is_match=`execute_command ${execute_user} ${primary_host} "${sys_bindir}/ksql -d esrep -h ${primary_host} -U esrep -p ${db_port}  -Atqc \"select conninfo from repmgr.nodes where node_id='$node_id';\" | grep -w "$scale_ip"|wc -l "`
        if [ "$is_match"x != "1"x ]
        then
            echo "[CONFIG_CHECK] node_id not match shrink_ip, exit!"
            exit 1
        fi
    fi
    echo "[CONFIG_CHECK] check node_id is in cluster ...OK"
}
function check_expand_type()
{
    local primary_host=$1
    if [ "$expand_type"x == "1"x ]
    then
        echo "[CONFIG_CHECK] current expand_type is witness, check witness node exist in cluster..."
        local node_exist=`execute_command ${execute_user} ${primary_host} "${sys_bindir}/ksql -d esrep -h ${primary_host} -U esrep -p ${db_port}  -Atqc \"select count(*) from repmgr.nodes where type='witness';\""`
        [ "$node_exist"x != "0"x ] && exit 1
        echo "[CONFIG_CHECK] current expand_type is witness, witness node not exist in cluster...OK"
    fi
}

function check_db_user()
{
    local ip=$1
    echo "[CONFIG_CHECK] check database connection ... "
    local is_connected_by_db_user=`execute_command ${execute_user} ${ip} "${sys_bindir}/ksql -d esrep -h ${ip} -U ${db_user} -p ${db_port}  -c \"select 999;\" | grep 999 |wc -l"`
    local is_connected_by_esrep=`execute_command ${execute_user} ${ip} "${sys_bindir}/ksql -d esrep -h ${ip} -U esrep -p ${db_port}  -c \"select 999;\" | grep 999 |wc -l"`
    if [ $is_connected_by_db_user -eq 1 ] && [ $is_connected_by_esrep -eq 1 ]
    then
        echo "[CONFIG_CHECK] check database connection ... OK"
    else
        if [ $is_connected_by_db_user -ne 1 ]
        then
            echo "[CONFIG_CHECK] param [ip:$ip db_name:esrep db_user:$db_user db_port:$db_port] set error in config file \"${install_conf}\" or in myself shell script"
        elif [ $is_connected_by_esrep -ne 1 ]
        then
            echo "[CONFIG_CHECK] param [ip:$ip db_name:esrep db_user:esrep db_port:$db_port] set error in config file \"${install_conf}\" or in myself shell script"
        fi
        exit 1
    fi
}

function check_db_running()
{
    # check if there is kingbase running on the host
    local ip=$1
    echo "[RUNNING] check the db is running or not..."
    local db_running=`execute_command ${super_user} $ip "netstat -apn 2>/dev/null|grep -w \"${db_port}\"|wc -l"`
    if [ $? -ne 0 -o "${db_running}"x != "0"x ]
    then
        should_exit=1
        echo "[ERROR] the db on \"${ip}:${db_port}\" is running, please stop it first."
    else
        echo "[RUNNING] the db is not running on \"${ip}:${db_port}\" ..... OK"
    fi
    [ $should_exit -eq 1 ] && exit 1
}
function set_param_from_cluster_conninfo()
{
    local param_name=$1
    local param_install_value=$2
    if [ "$param_name"x == "db_user"x ]
    then
        local param_conninfo_value=`execute_command ${execute_user} "$primary_host" "${sys_bindir}/repmgr cluster show |grep -w primary|awk -F \"|\" '{for(i=1;i<=NF;i++){print \\$i}}'|grep \"host=\" |tail -n 1 |  awk -F \" \" '{for(i=1;i<=NF;i++){print \\$i}}'|grep \"user=\" |tail -n 1|awk -F \"=\" '{ print \\$2 }' "`
    elif [ "$param_name"x == "db_name"x ]
    then
        local param_conninfo_value=`execute_command ${execute_user} "$primary_host" "${sys_bindir}/repmgr cluster show |grep -w primary|awk -F \"|\" '{for(i=1;i<=NF;i++){print \\$i}}'|grep \"host=\" |tail -n 1 |  awk -F \" \" '{for(i=1;i<=NF;i++){print \\$i}}'|grep \"dbname=\" |tail -n 1| awk -F \"=\" '{ print \\$2 }' "`
    elif [ "$param_name"x == "db_port"x ]
    then
        local param_conninfo_value=`execute_command ${execute_user} "$primary_host" "${sys_bindir}/repmgr cluster show |grep -w primary|awk -F \"|\" '{for(i=1;i<=NF;i++){print \\$i}}'|grep \"host=\" |tail -n 1  |  awk -F \" \" '{for(i=1;i<=NF;i++){print \\$i}}'|grep \"port=\" |tail -n 1| awk -F \"=\" '{ print \\$2 }' "`
    fi
    compare_param_diff "$param_name" "$param_install_value" "$param_conninfo_value"
    eval $param_name="$param_conninfo_value"
    echo " [INFO] $param_name=${param_conninfo_value}"
}
function set_param_from_cluster_conf()
{
    local key_value_conf=$1
    local param_name=$2
    local param_install_value=$3
    local param_conf_value=`read_conf_value "$primary_ip" "${key_value_conf}" "$param_name"`

    compare_param_diff "$param_name" "$param_install_value" "$param_conf_value"
    eval $param_name="$param_conf_value"
    echo " [INFO] $param_name=${param_conf_value}"
}
function compare_param_diff()
{
    local param_name=$1
    local install_param=$2
    local cluster_param=$3
    if [ "$cluster_param"x == ""x ]
    then
        echo "[WARNING] the ${install_conf} param[$param_name]:$cluster_param is null in cluster, please check cluster status,exit!"
        exit 1
    fi
    if [ "$install_param"x != "$cluster_param"x -a "$install_param"x != ""x ]
    then
        echo "[WARNING] the ${install_conf} param[$param_name]:$install_param is not same with cluster param[$param_name]:$cluster_param"
    fi
}

function check_install_conf()
{
    # check execute_user
    execute_command ${super_user} ${primary_ip} "test -f ${sys_bindir}/sys_monitor.sh"
    if [ $? -ne 0 ]
    then
        echo "[CONFIG_CHECK] \"${sys_bindir}/sys_monitor.sh\" is not exists on \"${ip}\", pelease check [install_dir] in config file \"${install_conf}\""
        exit 1
    fi
    local primary_execute_user=""
    primary_execute_user=`execute_command ${super_user} ${primary_ip} "stat -c %U ${sys_bindir}/sys_monitor.sh"`
    if [ $? -ne 0 ]
    then
        echo "[CONFIG_CHECK] get execute_user ... fail"
        exit 1
    fi
    if [ "$primary_execute_user"x != "$execute_user"x ]
    then
        echo "[CONFIG_CHECK] param [execute_user] set error in config file \"${install_conf}\" or in myself shell script"
        exit 1
    fi
    check_db_user "$primary_ip"
}

function check_net_device()
{
    local primary_ip=$1
    local expand_ip=$2
    local virtual_ip=$3
    local net_device=$4
    if [ "${virtual_ip}"x != ""x ]
    then
        vip=${virtual_ip%%/*}
        echo "[CONFIG_CHECK] The virtual ip [${vip}] exists on primary host [$primary_ip]....."
        local is_vip_exist=`${ping_path}/ping ${vip} -c 3 -w 3 | grep received | awk '{print $4}'`
        if [ $? -ne 0 ] || [ $is_vip_exist -gt 0 ]
        then
            local on_primary_host=`execute_command ${super_user} $primary_ip "${ipaddr_path}/ip addr | grep -w \"${vip}\" | wc -l"`
            if [ $? -ne 0 ] || ([ "$on_primary_host"x != ""x ] && [ $on_primary_host -eq 0 ])
            then
                echo "`date +'%Y-%m-%d %H:%M:%S'` The virtual ip [${vip}] has already exists and not on primary host [$primary_ip], exit."
                exit 1
            fi
        fi
        echo "[CONFIG_CHECK] The virtual ip [${vip}] exists on primary host [$primary_ip].....OK"
        echo "[CONFIG_CHECK] The net_device_ip:[${net_device_ip}] exists on dev ${net_device} on [${expand_ip}]....."

        ip_count=`execute_command ${super_user} ${expand_ip} "${ipaddr_path}/ip address show dev ${net_device} | grep -w \"${net_device_ip}\" | wc -l"`
        if [ $? -ne 0 ] || [ ${ip_count} -eq 0 ]
        then
            echo "[CONFIG_CHECK] net_device_ip:[${net_device_ip}] does not on host \"${expand_ip}\" on dev \"${net_device}\""
            exit 1
        fi
        echo "[CONFIG_CHECK] The net_device_ip:[${net_device_ip}] exists on host \"${expand_ip}\" on dev ${net_device} .....OK"
    fi
}
function check_primary_ip()
{
    local primary_ip=$1
    # check primary node is $primary_ip
    echo "[RUNNING] Primary node ip is $primary_ip ..."
    local is_primary=`execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show" |grep primary|grep running|grep $primary_ip |wc -l `
    if [ $is_primary -ne 1 ]
    then
        echo "[RUNNIN1G] Primary node ip is not $primary_ip,, check fail!"
        if [ "$on_bmj"x == "1"x ]
        then
            echo "[WARNING] current script owner is `stat -c %U $shell_folder/cluster_install.sh` ,on_bmj:${on_bmj},install_dir:${install_dir},if install_dir is not right,change current script owner as non-root!"
        fi
        exit 1
    fi
    echo "[RUNNING] Primary node ip is $primary_ip ... OK"
}
function expand_pre_check()
{
    check_install_conf

    check_script_node_position_local

    check_node_id "$primary_ip" "$node_id" "$expand_ip"

    check_expand_type "$primary_ip"

    check_db_running "$expand_ip"

    check_install_dir "$expand_ip"

    check_data_dir "$expand_ip"

    check_securecmdd "${expand_ip}"

    check_net_device "${primary_ip}" "${expand_ip}" "${virtual_ip}" "${net_device}"

    check_and_change_system "$expand_ip"

    check_and_cp_zip "$expand_ip"

    check_and_change_arping "$expand_ip"

    check_and_cp_license "$expand_ip"
}

function expand_stanby_node()
{
    change_repmgr_conf

    echo "[RUNNING] standby clone ..."
    execute_command ${execute_user} ${expand_ip} "$sys_bindir/repmgr -h $primary_ip -U esrep -d esrep -p $db_port -D $data_directory standby clone"
    [ $? -ne 0 ] && exit 1
    echo "[RUNNING] standby clone ...OK"

    echo "[RUNNING] db start ..."
    execute_command ${execute_user} ${expand_ip} "$sys_bindir/sys_ctl -w -t 60 -l ${install_dir}/logfile -D ${data_directory} start "
    [ $? -ne 0 ] && exit 1
    echo "[RUNNING] db start ...OK"

    execute_command ${execute_user} ${expand_ip} "$sys_bindir/repmgr standby register -F"
    execute_command ${execute_user} ${expand_ip} "$sys_bindir/sys_monitor.sh startlocal"
    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show"
}
function expand_witness_node()
{
    witness_ip=${expand_ip}
    primary_host=${primary_ip}
    # config secret-free configuration file .encpwd
    esrep_passwd="S2luZ2Jhc2VoYTExMA=="
    esrep_passwd_base64=`echo "${esrep_passwd}" | base64 -d`
    change_repmgr_conf
    create_witness_node
    execute_command ${execute_user} ${expand_ip} "$sys_bindir/sys_monitor.sh startlocal"
    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show"
}

function drop_standby_node()
{
    echo "[`date`] [INFO] ${sys_bindir}/repmgr standby unregister --node-id=$node_id ..."
    execute_command ${execute_user} ${primary_ip} "$sys_bindir/repmgr standby unregister --node-id=$node_id"
    [ $? -ne 0 ] && exit 1
    echo "[`date`] [INFO] ${sys_bindir}/repmgr standby unregister --node-id=$node_id ...OK"

    echo "[`date`] [INFO] check db connection ..."
    local is_connected=`execute_command ${execute_user} ${shrink_ip} "${sys_bindir}/ksql -d esrep -h ${shrink_ip} -U esrep -p ${db_port}  -c \"select 999;\" | grep 999 |wc -l"`
     if [ $is_connected -ne 1 ]
    then
        echo "[`date`] [INFO] can not connect to db on $shrink_ip, keep streaming replication running!  shrink done."
        execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show"
        exit 1
    fi
    echo "[`date`] [INFO] check db connection ...ok"
    sshstopdb $primary_ip $shrink_ip

    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/repmgr cluster show"

    slot_name="repmgr_slot_$node_id"

    echo "[`date`] [INFO]  drop replication slot:$slot_name..."
    execute_command ${execute_user} ${primary_ip} "${sys_bindir}/ksql -h $primary_ip -U esrep -d esrep -p $db_port -c \"select * from pg_drop_replication_slot('$slot_name');\""
    [ $? -ne 0 ] && exit 1
    echo "[`date`] [INFO]  drop replication slot:$slot_name...OK"
}

function expand()
{
    pre_exe

    expand_pre_check

    start_securecmdd "${expand_ip}"

    if [ $expand_type -eq 0 ]
    then
        expand_stanby_node
    elif [ $expand_type -eq 1 ]
    then
        expand_witness_node
    fi
}

function shrink()
{
    pre_exe

    shrink_pre_check "$primary_ip" "$shrink_ip"

    if [ $shrink_type -eq 0 ]
    then
        drop_standby_node
    elif [ $shrink_type -eq 1 ]
    then
        witness_ip=${shrink_ip}
        drop_witness_node
    fi
}
case $1 in
    "install")
    shift
    function_name="install"
    install
    exit 0
    ;;
    "expand")
    function_name="expand"
    expand
    exit 0
    ;;
    "shrink")
    function_name="shrink"
    shrink
    exit 0
    ;;
    "")
    function_name="install"
    install
    exit 0
    ;;
    *)
    echo "Do not choose any method, install/expand/shrink!"
    exit 1
esac
