#!/bin/bash

. /etc/profile >/dev/null 2>&1

umask 0022

current_dir=$(dirname $(readlink -f "$0"))
node_conf="${current_dir}/repmgr_config.conf"

function check_prm()
{
    prm=$1
    name=$2
    if [ "$prm"x = ""x ]
    then
        echo "[`date`] [ERROR] Parameter $name is empty, exit with error."
        exit 66
    fi
}

function check_prm_in_file()
{
    prm=$1
    name=$2
    if [ "$prm"x = ""x ]
    then
        echo "[`date`] [ERROR] Parameter $name is empty in \"$node_conf\", please set it in file at first."
        exit 66
    fi
}

function load_config()
{
    # no need to read file
    [ "$function_name"x = "stop_firewalld"x ] && return 0

    if [ -f $node_conf ]
    then
        while read t_one_line ; do eval ${t_one_line} ; done < $node_conf
    fi

    # check the default parameters
    [ "${ctl}"x = ""x ] && ctl=sys_ctl
    [ "${sql}"x = ""x ] && sql=ksql
    [ "${db_name}"x = ""x ] && db_name=test
    [ "${hba}"x = ""x ] && hba=sys_hba.conf
    [ "${db_conf}"x = ""x ] && db_conf=kingbase.conf
    [ "${encpwd}"x = ""x ] && encpwd=sys_encpwd

    [ "$function_name"x = "change_or_add_parm"x ] && return 0
	[ "$function_name"x = "stopdb"x ] && return 0
	[ "$function_name"x = "startdb"x ] && return 0
	[ "$function_name"x = "get_contrl"x ] && return 0

    check_prm_in_file "$bmj_flag" bmj_flag
    # only need the parameter 'bmj_flag', just return
    [ "$function_name"x = "change_system"x ] && return 0

    # check the common parameters
    check_prm_in_file "$node_id" node_id
    check_prm_in_file "$node_name" node_name
    check_prm_in_file "$conninfo" conninfo
    check_prm_in_file "$db_user" db_user
    check_prm_in_file "$db_port" db_port
    check_prm_in_file "$repmgr_conf" repmgr_conf
    check_prm_in_file "$scmd_port" scmd_port
    check_prm_in_file "$user_name" user_name
    check_prm_in_file "$cmp_ip" cmp_ip
    check_prm_in_file "$cmp_arping" cmp_arping
    check_prm_in_file "$cmp_ping" cmp_ping
}

#function_name Function name to will be called
function_name=$1
check_prm "$function_name" function_name

#read parameters from repmgr_config.conf
load_config

if [ "$function_name"x = "initdb"x ]
then
    #db_encoding Encoding format specified when initializing the database
    check_prm "$db_encoding" db_encoding
    #db_mode Compatible with oracle or pg or mysql
    check_prm "$db_mode" db_mode
    db_m=`echo ${db_mode} | tr '[A-Z]' '[a-z]'`

    check_prm "$auth_method" auth_method

    #db_password Specify user`s password when initializing database
    db_password=$2
    check_prm "$db_password" db_password

    #if $3 is not empty, it is waldir
    waldir=$3
elif [ "$function_name"x = "change_or_add_parm"x ]
then
    [ "$bmj_flag"x = ""x ] && bmj_flag=1
    #parameter Parameters to modify or add and their values  example:  "max_connection=100"
    parameter=$2
    check_prm "$parameter" parameter
    #conf_name The full path of the configuration file for the parameter to be modified or added  example: /home/kingbase/cluster/db/etc/repmgr.conf
    conf_name=$3
    check_prm "$conf_name" conf_name
elif [ "$function_name"x = "create_primary_node"x  ]
then
    #db_password Specify user`s password when initializing database 
    db_password=$2
    check_prm "$db_password" db_password
elif [ "$function_name"x = "create_standby_node"x ]
then
    #IP  Primary host ip
    IP=$2
    check_prm "$IP" IP
elif [ "$function_name"x = "create_witness_node"x ]
then
    #db_password Specify user`s password when initializing database
    db_password=$2
    check_prm "$db_password" db_password
    #IP  Primary host ip
    IP=$3
    check_prm "$IP" IP
elif [ "$function_name"x = "drop_standby_node"x ]
then
    #IP  Primary host ip
    IP=$2
    check_prm "$IP" IP
    #standby_ip  standby host ip
    standby_ip=$3
    check_prm "$standby_ip" standby_ip
    #standby_node_id Standby node id   example:  "standby_node_id=2"
    standby_node_id=$4
    check_prm "$standby_node_id" standby_node_id
elif [ "$function_name"x = "drop_witness_node"x ]
then
    #witness_ip  witness host ip
    witness_ip=$2
    check_prm "$witness_ip" witness_ip
    #witness_node_id Witness node id   example:  "witness_node_id=2"
    witness_node_id=$3
    check_prm "$witness_node_id" witness_node_id
elif [ "$function_name"x = "check_system"x ]
then
    #primary_flag Determine if the current node is primary or standby
    primary_flag=$2
    check_prm "$primary_flag" primary_flag
    ip_version=$3
    if [ "${ip_version}"x != ""x ]
    then
        ip_version=`echo ${ip_version} | tr '[A-Z]' '[a-z]'`
    else
        ip_version="ipv4"
    fi
fi

function check_res()
{
    RES=$1
    if [ $RES -eq 0 ]
    then
        echo "[`date`] [INFO] success"
    else
        echo "[`date`] [ERROR] The previous command failed to execute,errno:$RES"
        exit 66
    fi
}

function test_connect()
{
    local ip1="$1"
    local ip2="$2"

    [ "$ip1"x = ""x -a "$ip2"x = ""x ] && return 0

    if [ "$ip2"x = ""x ]
    then
        $current_dir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l root -T $ip1 "/bin/true 2>/dev/null"
        [ $? -eq 0 ] && return 0
        $current_dir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l root -T $ip1 "/usr/bin/true 2>/dev/null"
        [ $? -eq 0 ] && return 0
    else
        $current_dir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l root -T $ip1 "$current_dir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l root -T $ip2 \"/bin/true 2>/dev/null\""
        [ $? -eq 0 ] && return 0
        $current_dir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l root -T $ip1 "$current_dir/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l root -T $ip2 \"/usr/bin/true 2>/dev/null\""
        [ $? -eq 0 ] && return 0
    fi
    return 1
}

function check_system()
{
    if [ $bmj_flag -eq 0 ]
    then
        su_info=`su - $user_name -c "echo su_info_check"`
        if [ "${su_info}"x = ""x ]
        then
            echo "[`date`] [ERROR] [su - $user_name -c \"echo su_info_check\"] is null (should be: su_info_check)"
        elif [ "${su_info}"x != "su_info_check"x ]
        then
            echo "[`date`] [ERROR] [su - $user_name -c \"echo su_info_check\"] ${su_info} (should be: su_info_check)"
        else
            echo "[`date`] [INFO] [su - $user_name -c \"echo su_info_check\"] ${su_info}"
        fi

        file_num=`su - $user_name -c "ulimit -n 2>/dev/null" | tail -n 1`
        if [ "$file_num"x = ""x ]
        then
            echo "[`date`] [ERROR] [ulimit.open files] is null (no less than: 65535)"
        elif [ "${file_num}"x != "unlimited"x ] && [ $file_num -lt 65535 ]
        then
            echo "[`date`] [ERROR] [ulimit.open files] $file_num (no less than: 65535)"
        else
            echo "[`date`] [INFO] [ulimit.open files] $file_num"
        fi

        proc_num=`su - $user_name -c "ulimit -u 2>/dev/null" | tail -n 1`
        if [ "$proc_num"x = ""x ]
        then
            echo "[`date`] [ERROR] [ulimit.open proc] is null (no less than: 65535)"
        elif [ "${proc_num}"x != "unlimited"x ] && [ $proc_num -lt 65535 ]
        then
            echo "[`date`] [ERROR] [ulimit.open proc] $proc_num (no less than: 65535)"
        else
            echo "[`date`] [INFO] [ulimit.open proc] $proc_num"
        fi
    else
        file_num=`ulimit -n 2>/dev/null`
        if [ "$file_num"x = ""x ]
        then
            echo "[`date`] [ERROR] [ulimit.open files] is null (no less than: 65535)"
        elif [ "${file_num}"x != "unlimited"x ] && [ $file_num -lt 65535 ]
        then
            echo "[`date`] [ERROR] [ulimit.open files] $file_num (no less than: 65535)"
        else
            echo "[`date`] [INFO] [ulimit.open files] $file_num"
        fi

        proc_num=`ulimit -u 2>/dev/null`
        if [ "$proc_num"x = ""x ]
        then
            echo "[`date`] [ERROR] [ulimit.open proc] is null (no less than: 65535)"
        elif [ "${proc_num}"x != "unlimited"x ] && [ $proc_num -lt 65535 ]
        then
            echo "[`date`] [ERROR] [ulimit.open proc] $proc_num (no less than: 65535)"
        else
            echo "[`date`] [INFO] [ulimit.open proc] $proc_num"
        fi
    fi

    if [ "$all_ip"x != ""x ]
    then
        for ip1 in ${all_ip[@]}
        do
            test_connect $ip1
            if [ $? -ne 0 ]
            then
                echo "[`date`] [ERROR] [check connect] failed to connect $ip1 from current node"
                continue
            fi

            for ip2 in ${all_ip[@]}
            do
                test_connect $ip1 $ip2
                if [ $? -ne 0 ]
                then
                    echo "[`date`] [ERROR] [check connect] failed to connect $ip2 from $ip1"
                else
                    echo "[`date`] [INFO] [check connect] success to connect $ip2 from $ip1"
                fi
            done
        done
    else
        echo "[`date`] [WARNING] [check connect] the all_ip is NULL, unable to check connectivity between nodes"
    fi

    kernel_sem_value1=`sysctl kernel.sem 2>/dev/null |awk -F '=' '{print $2}'|awk '{print $1}'`
    kernel_sem_value2=`sysctl kernel.sem 2>/dev/null |awk -F '=' '{print $2}'|awk '{print $2}'`
    kernel_sem_value3=`sysctl kernel.sem 2>/dev/null |awk -F '=' '{print $2}'|awk '{print $3}'`
    kernel_sem_value4=`sysctl kernel.sem 2>/dev/null |awk -F '=' '{print $2}'|awk '{print $4}'`
    if [ "$kernel_sem_value1"x = ""x -o "$kernel_sem_value1"x = ""x  -o "$kernel_sem_value1"x = ""x -o "$kernel_sem_value1"x = ""x ]
    then
        echo "[`date`] [ERROR] [kernel.sem] is null (no less than: 5010 641280 5010 256)"
    elif [ $kernel_sem_value1 -lt 5010 -o $kernel_sem_value2 -lt 641280 -o $kernel_sem_value3 -lt 5010 -o $kernel_sem_value4 -lt 256 ]
    then
        echo "[`date`] [ERROR] [kernel.sem] $kernel_sem_value1 $kernel_sem_value2 $kernel_sem_value3 $kernel_sem_value4 (no less than: 5010 641280 5010 256)"
    else
        echo "[`date`] [INFO] [kernel.sem] $kernel_sem_value1 $kernel_sem_value2 $kernel_sem_value3 $kernel_sem_value4"
    fi

    RemoveIPC=`cat  /etc/systemd/logind.conf 2>/dev/null | grep ^RemoveIPC | tail -n 1`
    RemoveIPC_values=`echo $RemoveIPC | awk -F '=' '{print $2}'`
    RemoveIPC_v=`echo ${RemoveIPC_values} | tr '[A-Z]' '[a-z]'`
    if [ "$RemoveIPC_v"x = "no"x ]
    then
        echo "[`date`] [INFO] [RemoveIPC] $RemoveIPC_v"
    elif [ "$RemoveIPC_v"x = ""x ]
    then
        echo "[`date`] [WARNING] [RemoveIPC] is null"
    else
        echo "[`date`] [ERROR] [RemoveIPC] $RemoveIPC_v (should be: no)"
    fi

    DefaultTasksAccounting=`cat /etc/systemd/system.conf 2>/dev/null | grep ^DefaultTasksAccounting | tail -n 1`
    DefaultTasksAccounting_values=`echo $DefaultTasksAccounting | awk -F '=' '{print $2}'`
    DefaultTasksAccounting_v=`echo ${DefaultTasksAccounting_values} | tr '[A-Z]' '[a-z]'`

    if [ "$DefaultTasksAccounting_v"x = "no"x ]
    then
        echo "[`date`] [INFO] [DefaultTasksAccounting] $DefaultTasksAccounting_v"
    elif [ "$DefaultTasksAccounting_v"x = ""x ]
    then    
        echo "[`date`] [INFO] [DefaultTasksAccounting] is null "
    else
        echo "[`date`] [ERROR] [DefaultTasksAccounting] $DefaultTasksAccounting_v (should be: no)"
    fi

    cron_path=`which crond 2>/dev/null`
    if [ "$cron_path"x = ""x ]
    then
        cron_path=`which cron 2>/dev/null`
        if [ "$cron_path"x = ""x ]
        then
            echo "[`date`] [WARNING] Can not use command [which] to find [cron/crond service], it may not exist, please set cron/crond service active!!!"
        else
            cron_name=cron
        fi
    else
        cron_name=crond
    fi

    limit=`systemctl status "$cron_name" 2>/dev/null | tr '[A-Z]' '[a-z]' | sed -n "/tasks: [0-9]* (limit: [0-9]*)/p"`
    if [ "$limit"x != ""x ]
    then
        tasks=`echo "$limit" | sed "s/.*limit: \(.*\))$/\1/g"`
        if [ "$tasks"x = ""x ]
        then
            echo "[`date`] [INFO] [systemd limit] is null (no less than: 65535)"
        elif [ $tasks -lt 65535 ]
        then
            echo "[`date`] [WARNING] [systemd limit] $tasks (no less than: 65535)"
        else
            echo "[`date`] [INFO] [systemd limit] $tasks"
        fi
    fi

    SELINUX=`getenforce 2>/dev/null`
    SELINUX_values=`echo ${SELINUX} | tr '[A-Z]' '[a-z]'`

    if [ "$SELINUX_values"x = "disabled"x -o "$SELINUX_values"x = "permissive"x ]
    then
        echo "[`date`] [INFO] [SELINUX] $SELINUX_values"
    elif [ "$SELINUX_values"x = ""x ]
    then
        echo "[`date`] [INFO] [SELINUX] is null"
    else
        echo "[`date`] [WARNING] [SELINUX] $SELINUX_values (should be: disabled or permissive)"
    fi

    service iptables status 1>/dev/null 2>&1
    iptables_flag=$?

    service firewalld status 1>/dev/null 2>&1
    firewalld_flag=$?

    service ufw status 1>/dev/null 2>&1 
    ufw_flag=$?

    if [ "$iptables_flag"x = "0"x -o "$firewalld_flag"x = "0"x -o "$ufw_flag"x = "0"x ]
    then
        echo "[`date`] [WARNING] [firewall] up (should be: down or add port rules)"
    else
        echo "[`date`] [INFO] [firewall] down"
    fi

    if [ "$db_port"x != ""x ]
    then
        port_exist=`netstat -an | grep -w $db_port |grep -w "LISTEN" |wc -l`
        if [ "$port_exist"x != "0"x ]
        then
            echo "[`date`] [ERROR] [$db_port] already occupied"
        else
            echo "[`date`] [INFO] [$db_port] OK"
        fi
    else
        if [ "$PG_FLAG" = "1"x ]
        then
            port_exist=`netstat -an | grep -w 5432 |grep -w "LISTEN"  |wc -l`
            if [ "$port_exist"x != "0"x ]
            then
                echo "[`date`] [ERROR] [5432] already occupied"
            else
                echo "[`date`] [INFO] [5432] OK"
            fi
        else
            port_exist=`netstat -an | grep -w 54321 |grep -w "LISTEN"  |wc -l`
            if [ "$port_exist"x != "0"x ]
            then
                echo "[`date`] [ERROR] [54321] already occupied"
            else
                echo "[`date`] [INFO] [5432] OK"
            fi
        fi
    fi

    if [ -e $data_path ]
    then
        echo "[`date`] [ERROR] [Data directory] already exists"
    else
        echo "[`date`] [INFO] [Data directory] OK"
    fi

    mem=`cat /proc/meminfo |grep -w "MemFree" |awk '{print $2}'`
    if [ "$mem"x = ""x ]
    then
        echo "[`date`] [WARNING] [The memory] is null (no less than 1G)"
    elif [ $mem -lt 1048576 ]
    then
        echo "[`date`] [WARNING] [The memory] $mem kb (no less than 1G)"
    else
        echo "[`date`] [INFO] [The memory] OK"
    fi

    if [ $bmj_flag -eq 0 ]
    then
        df_path=/home/$user_name
    else
        df_path=/opt
    fi

    hard_disk=`df $df_path -P 2>/dev/null |head -n 2| tail -n +2|awk '{print $4}'`
    if [ "$hard_disk"x = ""x ]
    then
        echo "[`date`] [ERROR] [The hard disk] is null (no less than 1G)"
    elif [ $hard_disk -lt 1048576 ]
    then
        echo "[`date`] [ERROR] [The hard disk] $hard_disk (no less than 1G)"
    else
        echo "[`date`] [INFO] [The hard disk] OK"
    fi

    if [ "${ip_version}"x = "ipv4"x ]
    then
        ping_c=`ls $cmp_ping/ping 2>/dev/null`
        ping_exist=$?
        if [ "$ping_exist"x != "0"x ]
        then
            echo "[`date`] [ERROR] [ping command path] $cmp_ping incorrect"
        else
            echo "[`date`] [INFO] [ping command path] OK"
        fi
    else
        ping6_c=`ls $cmp_ping/ping6 2>/dev/null`
        ping6_exist=$?
        if [ "$ping6_exist"x != "0"x ]
        then
            echo "[`date`] [ERROR] [ping6 command path] $cmp_ping incorrect"
        else
            echo "[`date`] [INFO] [ping6 command path] OK"
        fi
    fi
    /bin/cp --version >/dev/null 2>&1
    cp_exist=$?
    if [ "$cp_exist"x != "0"x ]
    then
        echo "[`date`] [ERROR] [/bin/cp --verison] execute failed"
    else
        echo "[`date`] [INFO] [/bin/cp --version] OK"
    fi

    if [ "$vip"x = ""x ]
    then
        echo "[`date`] [INFO] [Virtual IP] Not configured"
    else
        vip_ip=${vip%%/*}
        ip_c=`ls $cmp_ip/ip 2>/dev/null`
        ip_exist=$?
        if [ "$ip_exist"x != "0"x ]
        then
            echo "[`date`] [ERROR] [ip command path] $cmp_ip incorrect"
        else
            echo "[`date`] [INFO] [ip command path] OK"
        fi

        arping_c=`ls $cmp_arping/arping 2>/dev/null`
        arping_exist=$?
        if [ "$arping_exist"x != "0"x ]
        then
            echo "[`date`] [ERROR] [arping command path] $cmp_arping incorrect"
        else
            echo "[`date`] [INFO] [arping command path] OK"
        fi

        arping_U=`$cmp_arping/arping --help 2>&1 |grep -wF -e "-U" |wc -l`
        if [ "$arping_U"x = "0"x ]
        then
            echo "[`date`] [ERROR] [arping -U command] incorrect"
        else
            echo "[`date`] [INFO] [arping -U command] OK"
        fi

        local is_ipv6=`echo "$vip_ip" | grep -o ":" | wc -l`
        if [ $primary_flag -eq 1 ]
        then
            if [ ${is_ipv6} -eq 0 ]
            then
                regex="\b(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[1-9])\b"
                ckip=`echo $vip_ip | egrep $regex | wc -l`
                if [ $ckip -eq 0 ]
                then
                    echo "[`date`] [ERROR] [Virtual IP] $vip (should be: IP)"
                else
                    vip_ping=`ping $vip_ip -c 3 2>/dev/null |grep -w "received" |awk '{print $4}'`
                    vip_exist=`ip addr |grep -w "$vip_ip"|wc -l`
                    if [ "$vip_ping"x != "0"x -a "$vip_exist"x = "0"x ]
                    then
                        echo "[`date`] [ERROR] [Virtual IP] $vip Cannot use"
                    else
                        echo "[`date`] [INFO] [Virtual IP] $vip OK"
                    fi
                fi
            else
                vip_ping=`ping6 $vip_ip -c 3 2>/dev/null |grep -w "received" |awk '{print $4}'`
                vip_exist=`ip addr |grep -w "$vip_ip"|wc -l`
                if [ "$vip_ping"x != "0"x -a "$vip_exist"x = "0"x ]
                then
                    echo "[`date`] [ERROR] [Virtual IP] $vip Cannot use"
                else
                    echo "[`date`] [INFO] [Virtual IP] $vip OK" 
                fi
            fi
        fi
    fi
}

function change_system()
{
    if [ -f /etc/security/limits.conf ];then
        echo "[`date`] [INFO] change ulimit ..."
        echo "
*       soft        nofile      655360
root    soft        nofile      655360
*       hard        nofile      655360
root    hard        nofile      655360
*       soft        nproc       655360
root    soft        nproc       655360
*       hard        nproc       655360
root    hard        nproc       655360
*       soft        core        unlimited
root    soft        core        unlimited
*       hard        core        unlimited
root    hard        core        unlimited
*       soft        memlock     50000000
root    soft        memlock     50000000
*       hard        memlock     50000000
root    hard        memlock     50000000" >> /etc/security/limits.conf
        /bin/rm -rf /etc/security/limits.d/*
        echo "[`date`] [INFO] change ulimit ... Done"
    else
        echo "[`date`] [WARNING] there is no file \"/etc/security/limits.conf\" found"
    fi

    if [ -f /etc/sysctl.conf ];then
        echo "[`date`] [INFO] change kernel.sem ..."
        echo "
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
net.core.somaxconn=4096" >> /etc/sysctl.conf
        echo "[`date`] [INFO] change kernel.sem ... Done"
    else
        echo "[`date`] [WARNING] there is no file \"/etc/sysctl.conf\" found"
    fi

    if [ $bmj_flag -eq 0 ]
    then
        su_changed=`grep -w "^[ ]*/usr/bin/failinfo$" /etc/profile 2>/dev/null`
        if [ "${su_changed}"x != ""x ]
        then
            echo "[`date`] [INFO] delete '/usr/bin/failinfo' in \"/etc/profile\" ..."
            sed -i "s|^[ ]*/usr/bin/failinfo$|#/usr/bin/failinfo|g" /etc/profile
            echo "[`date`] [INFO] delete '/usr/bin/failinfo' in \"/etc/profile\" ... Done"
        else
            echo "[`date`] [INFO] no need to change \"/etc/profile\""
        fi

        if [ -f /etc/selinux/config ];then
            echo "[`date`] [INFO] stop selinux ..."
            setenforce 0 > /dev/null 2>&1
            sed -i "s/^SELINUX[ ]*=/#SELINUX=/g" /etc/selinux/config
            echo "" >> /etc/selinux/config
            echo "SELINUX=disabled" >> /etc/selinux/config
            echo "[`date`] [INFO] stop selinux ... Done"
        else
            echo "[`date`] [WARNING] there is no file \"/etc/selinux/config\" found"
        fi

        if [ -f /etc/systemd/logind.conf ];then
            echo "[`date`] [INFO] change RemoveIPC ..."
            sed -i "s/^RemoveIPC[ ]*=/#RemoveIPC=/g" /etc/systemd/logind.conf
            echo "" >>  /etc/systemd/logind.conf
            echo "RemoveIPC=no" >>  /etc/systemd/logind.conf
            echo "[`date`] [INFO] change RemoveIPC ... Done"
        else
            echo "[`date`] [WARNING] there is no file \"/etc/systemd/logind.conf\" found"
        fi

        if [ -f /etc/systemd/system.conf ];then
            echo "[`date`] [INFO] change DefaultTasksAccounting ..."
            sed -i "s/^DefaultTasksAccounting[ ]*=/#DefaultTasksAccounting=/g" /etc/systemd/system.conf
            echo "" >> /etc/systemd/system.conf
            echo "DefaultTasksAccounting=no" >> /etc/systemd/system.conf
            echo "[`date`] [INFO] change DefaultTasksAccounting ... Done"
        else
            echo "[`date`] [WARNING] there is no file \"/etc/systemd/system.conf\" found"
        fi
    else
        if [ -f /etc/systemd/logind.conf ];then
            echo "[`date`] [INFO] change RemoveIPC ..."
            sed "s/^RemoveIPC[ ]*=/#RemoveIPC=/g" /etc/systemd/logind.conf > /etc/systemd/config_temp
            cat /etc/systemd/config_temp > /etc/systemd/logind.conf
            /bin/rm -f /etc/systemd/config_temp
            echo "" >>  /etc/systemd/logind.conf
            echo "RemoveIPC=no" >>  /etc/systemd/logind.conf
            echo "[`date`] [INFO] change RemoveIPC ... Done"
        else
            echo "[`date`] [WARNING] there is no file \"/etc/systemd/logind.conf\" found"
        fi

        if [ -f /etc/systemd/system.conf ];then
            echo "[`date`] [INFO] change DefaultTasksAccounting ..."
            sed "s/^DefaultTasksAccounting[ ]*=/#DefaultTasksAccounting=/g" /etc/systemd/system.conf > /etc/systemd/config_temp
            cat /etc/systemd/config_temp > /etc/systemd/system.conf
            /bin/rm -f /etc/systemd/config_temp
            echo "" >> /etc/systemd/system.conf
            echo "DefaultTasksAccounting=no" >> /etc/systemd/system.conf
            echo "[`date`] [INFO] change DefaultTasksAccounting ... Done"
        else
            echo "[`date`] [WARNING] there is no file \"/etc/systemd/system.conf\" found"
        fi
    fi

    echo "[`date`] [INFO] configuration to take effect ..."
    if [ -f /etc/sysctl.conf ];then
        sysctl -p > /dev/null
    fi
    if [ $bmj_flag -eq 0 ]
    then
        if [ -f /etc/systemd/logind.conf -o /etc/systemd/system.conf ];then
            systemctl daemon-reload 1>/dev/null 2>&1
        fi
    fi
    echo "[`date`] [INFO] configuration to take effect ... Done"
}

function stop_firewalld()
{
    echo "[`date`] [INFO] stop firewalld ..."
    systemctl disable  firewalld 1>/dev/null 2>&1
    service firewalld stop 1>/dev/null 2>&1
    service iptables stop 1>/dev/null 2>&1
    chkconfig iptables off 1>/dev/null 2>&1
    service ip6tables stop 1>/dev/null 2>&1
    chkconfig ip6tables off 1>/dev/null 2>&1
    systemctl disable ufw 1>/dev/null 2>&1
    service ufw stop 1>/dev/null 2>&1
    echo "[`date`] [INFO] stop firewalld ... Done"
}

function initdb()
{
    initdb_options=""
    if [ "${data_checksums}"x = "yes"x -o "${data_checksums}"x = "on"x -o "${data_checksums}"x = "true"x -o "${data_checksums}"x = "1"x ]
    then
        initdb_options="--data-checksums"
    fi

    local all_tmp_ip=(${all_ip[@]})
    # if the number of members of all_ip is greater than 1, it must initdb for witness node.
    if [ "$waldir"x != ""x ] && [ ${#all_tmp_ip[@]} -eq 1 ]
    then
        initdb_options="${initdb_options} --waldir=$waldir"
    fi

    [ "$collate"x != ""x ] && initdb_options="${initdb_options} --lc-collat=${collate}"
    [ "$cType"x != ""x ] && initdb_options="${initdb_options} --lc-ctype=${cType}"
    [ "${db_other_options}"x != ""x ] && initdb_options="${initdb_options} ${db_other_options}"
    [ "${eCharacterSetCheck}"x == "true"x ] && db_encoding="${eCharacterSet}"

    if [ "$db_m"x = "pg"x ]
    then
        echo "[`date`] [INFO] $db_bin/initdb -U \"$db_user\" -E $db_encoding -m pg -D $data_path -A $auth_method -x $db_password $other_par $initdb_options"
        $db_bin/initdb -U "$db_user" -E $db_encoding -m pg -D $data_path -A $auth_method -x $db_password $other_par $initdb_options
        RETVAL=$?
        check_res $RETVAL
        echo "" >> $data_path/$db_conf
        echo "include_if_exists='./es_rep.conf'" >> $data_path/$db_conf
        spl_exist=`grep -wRn "#shared_preload_libraries" $data_path/$db_conf |wc -l`
        if [ $spl_exist -eq 1 ]
        then
            echo "shared_preload_libraries = 'repmgr'" >> $data_path/$db_conf
        else
            sed "/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/" $data_path/$db_conf > $data_path/conf.temp
            cat $data_path/conf.temp > $data_path/$db_conf && /bin/rm -f $data_path/conf.temp
        fi
        echo "host    replication     all             0.0.0.0/0              $auth_method" >> $data_path/$hba
        echo "host    all             all             0.0.0.0/0              $auth_method" >> $data_path/$hba
        echo "host    replication     all             ::0/0                  $auth_method" >> $data_path/$hba
    elif [ "$db_m"x = "mysql"x ]
    then
        echo "[`date`] [INFO] $db_bin/initdb -U \"$db_user\" -E $db_encoding -m mysql -D $data_path -A $auth_method -x $db_password $other_par $initdb_options"
        $db_bin/initdb -U "$db_user" -E $db_encoding -m mysql -D $data_path -A $auth_method -x $db_password $other_par $initdb_options
        RETVAL=$?
        check_res $RETVAL
        echo "" >> $data_path/$db_conf
        echo "include_if_exists='./es_rep.conf'" >> $data_path/$db_conf
        spl_exist=`grep -wRn "#shared_preload_libraries" $data_path/$db_conf |wc -l`
        if [ $spl_exist -eq 1 ]
        then
            echo "shared_preload_libraries = 'libmysql_parser,repmgr'" >> $data_path/$db_conf
        else
            sed "/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/" $data_path/$db_conf > $data_path/conf.temp
            cat $data_path/conf.temp > $data_path/$db_conf && /bin/rm -f $data_path/conf.temp
        fi
        echo "host    replication     all             0.0.0.0/0              $auth_method" >> $data_path/$hba
        echo "host    all             all             0.0.0.0/0              $auth_method" >> $data_path/$hba
        echo "host    replication     all             ::0/0                  $auth_method" >> $data_path/$hba
    else
        echo "[`date`] [INFO] $db_bin/initdb -U \"$db_user\" -E $db_encoding -m oracle -D $data_path -A $auth_method -x $db_password $other_par $initdb_options"
        $db_bin/initdb -U "$db_user" -E $db_encoding -m oracle -D $data_path -A $auth_method -x $db_password $other_par $initdb_options
        RETVAL=$?
        check_res $RETVAL
        echo "" >> $data_path/$db_conf
        echo "include_if_exists='./es_rep.conf'" >> $data_path/$db_conf
        spl_exist=`grep -wRn "#shared_preload_libraries" $data_path/$db_conf |wc -l`
        if [ $spl_exist -eq 1 ]
        then
            echo "shared_preload_libraries = 'liboracle_parser,repmgr'" >> $data_path/$db_conf
        else
            sed "/^shared_preload_libraries[ ]*=[ ]*'*'/s/'/'repmgr,/" $data_path/$db_conf > $data_path/conf.temp
            cat $data_path/conf.temp > $data_path/$db_conf && /bin/rm -f $data_path/conf.temp
        fi
        echo "host    replication     all             0.0.0.0/0              $auth_method" >> $data_path/$hba
        echo "host    all             all             0.0.0.0/0              $auth_method" >> $data_path/$hba
        echo "host    replication     all             ::0/0                  $auth_method" >> $data_path/$hba
    fi
}

function change_or_add_parm()
{
    local delimiter=""

    echo "[`date`] [INFO] PARAMETER_NAME=`echo $parameter |awk -F "=" '{print $1}'`"
    PARAMETER_NAME=`echo $parameter |awk -F "=" '{print $1}'`
    RETVAL=$?
    check_res $RETVAL
    echo "[`date`] [INFO] PARAMETER_VALUES=`echo $parameter |awk -F "=" '{print $2}'`"
    PARAMETER_VALUES=`echo $parameter |awk -F "=" '{print $2}'`
    RETVAL=$?
    check_res $RETVAL

    if [ "$PARAMETER_NAME"x != ""x -a "$PARAMETER_VALUES"x != ""x -a "$PARAMETER_VALUES"x != "''"x ]
    then
        delimiter="="
    elif [ "$PARAMETER_VALUES"x = ""x ] && [ "`echo $parameter | grep = | wc -l`"x = "0"x  ]
    then
        local value1=""
        local value2=""
        value1=`echo $parameter | awk -F " " '{print $1}' 2>/dev/null`
        value2=`echo $parameter | awk -F " " '{print $2}' 2>/dev/null`
        if [ "$value1"x != ""x -a "$value2"x != ""x -a "$value2"x != "''"x ]
        then
            echo "[`date`] [INFO] PARAMETER_NAME=${value1}"
            PARAMETER_NAME="${value1}"
            echo "[`date`] [INFO] PARAMETER_VALUES=${value2}"
            PARAMETER_VALUES="${value2}"
            delimiter="[ ]"
        fi
    fi

    if [ "${delimiter}"x != ""x ]
    then
        if [ "$PARAMETER_NAME"x = "sys_bindir"x ]
        then
            if [ "$ctl"x = "sys_ctl"x ]
            then
                parameter="sys_bindir=$PARAMETER_VALUES"
                PARAMETER_NAME=sys_bindir
            else
                parameter="pg_bindir=$PARAMETER_VALUES"
                PARAMETER_NAME=pg_bindir
            fi
        fi

        echo "[`date`] [INFO] PARM_EXIST=`grep -wRn $PARAMETER_NAME $conf_name |wc -l`"
        PARM_EXIST=`grep -wRn $PARAMETER_NAME $conf_name |wc -l`
        RETVAL=$?
        check_res $RETVAL

        if [ $PARM_EXIST -eq 0 ]
        then
            local need_chown=""
            local current_user=""
            local file_owner=""

            if [ ! -f $conf_name ]
            then
                current_user=`id -un 2>/dev/null`
                file_owner=`stat -c %U $0 2>/dev/null` || file_owner=`ls -l $0 2>/dev/null | awk '{print $3}'`
                if [ "$file_owner"x != ""x ] && [ "$file_owner"x != "$current_user"x ]
                then
                    need_chown="true"
                fi
            fi
            echo "[`date`] [INFO] \"$parameter\" >> $conf_name"
            echo "$parameter" >> $conf_name
            RETVAL=$?
            check_res $RETVAL
            if [ "$need_chown"x = "true"x ]
            then
                chown ${file_owner} $conf_name
                chmod 664 $conf_name
            fi
        else
            if [ $bmj_flag -eq 0 ]
            then
                echo "[`date`] [INFO] sed -i \"/[#]*${PARAMETER_NAME}[ ]*${delimiter}/c${parameter}\" $conf_name"
                sed -i "/^[# ]*${PARAMETER_NAME}[ ]*${delimiter}/c${parameter}" $conf_name
                RETVAL=$?
                check_res $RETVAL
            else
                echo "[`date`] [INFO] sed \"/[#]*${PARAMETER_NAME}[ ]*${delimiter}/c${parameter}\" $conf_name > $current_dir/conf.temp"
                sed "/^[# ]*${PARAMETER_NAME}[ ]*${delimiter}/c${parameter}" $conf_name > $current_dir/conf.temp
                RETVAL=$?
                check_res $RETVAL
                echo "[`date`] [INFO] cat $current_dir/conf.temp > $conf_name"
                cat $current_dir/conf.temp > $conf_name
                RETVAL=$?
                check_res $RETVAL
                /bin/rm -f $current_dir/conf.temp 2>/dev/null
            fi
        fi
    fi
}

function startdb()
{
    if [ "$db_port"x = ""x ]
    then       
        echo "[`date`] [INFO] $db_bin/$ctl start -w -t 90 -D $data_path  "
        $db_bin/$ctl start -w -t 90 -D $data_path 
        RETVAL=$?
        check_res $RETVAL
    else
        echo "[`date`] [INFO] $db_bin/$ctl start -w -t 90 -D $data_path -o --port=$db_port"
        $db_bin/$ctl start -w -t 90 -D $data_path -o --port=$db_port
        RETVAL=$?
        check_res $RETVAL
    fi
    
}

function stopdb()
{
    echo "[`date`] [INFO] $db_bin/$ctl stop -w -t 90 -D $data_path"
    $db_bin/$ctl stop -w -t 90 -D $data_path
    RETVAL=$?
    check_res $RETVAL
}

function sshstopdb()
{
    echo "[`date`] [INFO] $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $standby_ip \"$db_bin/sys_monitor.sh stoplocal 2>/dev/null\""
    $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $standby_ip "$db_bin/sys_monitor.sh stoplocal 2>/dev/null"
    RETVAL=$?
    if [ $RETVAL -eq 0 ]
    then
        echo "[`date`] [INFO] stop standby db success."
    elif [ $RETVAL -eq 255 ]
    then
        echo "[`date`] [INFO] sys_securecmd failed to connect to the standby machine."
    else
        db_exsit=`$db_bin/$sql -h $IP -U esrep -d esrep -p $db_port -c "select * from pg_stat_replication;" |grep -w "$standby_ip" |wl -c`
        if [ $db_exsit -eq 0 ]
        then
            echo "[`date`] [INFO] stop standby db failed,but But the streaming replication connection of db has been disconnected, which does not affect the delete replication slot operation."
        else
            echo "[`date`] [ERROR] stop standby db failed,the stream replication connection of db still exists, which affects the host to delete the replication slot and exits with an error."
            exit 66
        fi
    fi
}

function sshstopwitness()
{
    echo "[`date`] [INFO] $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $witness_ip \"$db_bin/sys_monitor.sh stoplocal 2>/dev/null\""
    $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $witness_ip "$db_bin/sys_monitor.sh stoplocal 2>/dev/null"
    RETVAL=$?
    if [ $RETVAL -eq 0 ]
    then
        echo "[`date`] [INFO] stop witness db success."
    elif [ $RETVAL -eq 255 ]
    then
        echo "[`date`] [INFO] sys_securecmd failed to connect to the standby machine."
    else
        echo "[`date`] [INFO] stop witness db failed."
    fi
}

function create_superuser()
{
    esrep_password="S2luZ2Jhc2VoYTExMA=="
    esrep_real_password=`echo $esrep_password |base64 -d`
    echo "[`date`] [INFO] $db_bin/$sql -U \"$db_user\" -d $db_name -p $db_port -c \"create user \"esrep\" with superuser PASSWORD '******';\""
    $db_bin/$sql -U "$db_user" -d $db_name -p $db_port -c "create user \"esrep\" with superuser PASSWORD '${esrep_real_password}';"
    RETVAL=$?
    check_res $RETVAL
    echo "[`date`] [INFO] $db_bin/$sql -U esrep -d $db_name -p $db_port -c \"create database \"esrep\";\""
    $db_bin/$sql -U esrep -d $db_name -p $db_port -c "create database \"esrep\" ;"
    RETVAL=$?
    check_res $RETVAL
}

function create_witness_superuser()
{
    if [ -f ~/.encpwd ]
    then
        esrep_password=`grep "esrep:" ~/.encpwd | awk -F : '{print $5}'`
        if [ -z "$esrep_password" ]
        then
            echo "[`date`] [WARNING] can not read esrep password from ~/.encpwd, set default password"
            esrep_password="S2luZ2Jhc2VoYTExMA=="
        fi
    else
        esrep_password="S2luZ2Jhc2VoYTExMA=="
    fi
    esrep_real_password=`echo $esrep_password |base64 -d`
    echo "[`date`] [INFO] $db_bin/$sql -U \"$db_user\" -d $db_name -p $db_port -c \"create user \"esrep\" with superuser PASSWORD '******';\""
    $db_bin/$sql -U "$db_user" -d $db_name -p $db_port -c "create user \"esrep\" with superuser PASSWORD '${esrep_real_password}';"
    RETVAL=$?
    check_res $RETVAL
    echo "[`date`] [INFO] $db_bin/$sql -U esrep -d $db_name -p $db_port -c \"create database \"esrep\";\""
    $db_bin/$sql -U esrep -d $db_name -p $db_port -c "create database \"esrep\" ;"
    RETVAL=$?
    check_res $RETVAL
}

function set_pass()
{
    if [ -f ~/.encpwd ]
    then
        /bin/rm -f ~/.encpwd
    fi
    esrep_password="S2luZ2Jhc2VoYTExMA=="
    esrep_real_password=`echo $esrep_password |base64 -d`
    $db_bin/$encpwd -H \* -P \* -D \* -U $db_user -W $db_password
    RETVAL=$?
    check_res $RETVAL
    $db_bin/$encpwd -H \* -P \* -D \* -U esrep -W $esrep_real_password
    RETVAL=$?
    check_res $RETVAL
}

function set_pass_witness()
{
    if [ -f ~/.encpwd ]
    then
        /bin/rm -f ~/.encpwd
    fi
    echo "[`date`] [INFO] $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $IP \"cat ~/.encpwd \" > ~/.encpwd"
    $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $IP "cat ~/.encpwd " > ~/.encpwd
    RETVAL=$?
    check_res $RETVAL
    chmod 600 ~/.encpwd
    RETVAL=$?
    check_res $RETVAL

    $db_bin/$encpwd -H \* -P \* -D \* -U $db_user -W $db_password
    RETVAL=$?
    check_res $RETVAL

    esrep_password=`grep "esrep:" ~/.encpwd | awk -F : '{print $5}'`
    if [ -z "$esrep_password" ]
    then
        echo "[`date`] [WARNING] can not read esrep password from ~/.encpwd, set default password"
        esrep_password="S2luZ2Jhc2VoYTExMA=="
        esrep_real_password=`echo $esrep_password |base64 -d`
        $db_bin/$encpwd -H \* -P \* -D \* -U esrep -W $esrep_real_password
        RETVAL=$?
        check_res $RETVAL
    fi
}

function change_hba()
{
    if [ $bmj_flag -eq 0 ]
    then
        echo "[`date`] [INFO] sed -i \"s/trust/md5/\" $data_path/$hba"
        sed -i "s/trust/md5/g" $data_path/$hba
        RETVAL=$?
        check_res $RETVAL
    else
        echo "[`date`] [INFO] sed \"s/trust/md5/\" $data_path/$hba > $db_bin/hba_conf.temp"
        sed "s/trust/md5/g" $data_path/$hba > $db_bin/hba_conf.temp
        RETVAL=$?
        check_res $RETVAL
        echo "cat $db_bin/hba_conf.temp > $data_path/$hba"
        cat $db_bin/hba_conf.temp > $data_path/$hba
        RETVAL=$?
        check_res $RETVAL
    fi
}

function register_primary()
{
    echo "[`date`] [INFO] $db_bin/repmgr primary register"
    $db_bin/repmgr primary register
    RETVAL=$?
    check_res $RETVAL
}

function register_standby()
{
    echo "[`date`] [INFO] $db_bin/repmgr standby register -F"
    $db_bin/repmgr standby register -F
    RETVAL=$?
    check_res $RETVAL
}

function register_witness()
{
    echo "[`date`] [INFO] $db_bin/repmgr -h $IP -p $db_port witness register"
    $db_bin/repmgr -h $IP -p $db_port witness register
    RETVAL=$?
    check_res $RETVAL
}

function unregister_standby()
{
    echo "[`date`] [INFO] $db_bin/repmgr standby unregister --node-id=$standby_node_id"
    $db_bin/repmgr standby unregister --node-id=$standby_node_id
    RETVAL=$?
    check_res $RETVAL
}

function unregister_witness()
{
    echo "[`date`] [INFO] $db_bin/repmgr witness unregister --node-id=$witness_node_id"
    $db_bin/repmgr witness unregister --node-id=$witness_node_id
    RETVAL=$?
    check_res $RETVAL
}

function clone_standby()
{
    echo "[`date`] [INFO] $db_bin/repmgr -h $IP -U esrep -d esrep -p $db_port -D $data_path standby clone"
    $db_bin/repmgr -h $IP -U esrep -d esrep -p $db_port -D $data_path standby clone
    RETVAL=$?
    check_res $RETVAL
}

function cp_conf()
{
    echo "[`date`] [INFO] $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $IP \"cat $repmgr_conf \" > $repmgr_conf"
    $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $IP "cat $repmgr_conf " > $repmgr_conf
    RETVAL=$?
    check_res $RETVAL
    echo "[`date`] [INFO] $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $IP \"cat ~/.encpwd \" > ~/.encpwd"
    $db_bin/sys_securecmd -p $scmd_port -o StrictHostKeyChecking=no -o ConnectTimeout=10 -l $user_name -T $IP "cat ~/.encpwd " > ~/.encpwd
    RETVAL=$?
    check_res $RETVAL
    chmod 600 ~/.encpwd
    RETVAL=$?
    check_res $RETVAL
}

function drop_standby_slot()
{
    slot_name="repmgr_slot_$standby_node_id"
    echo "[`date`] [INFO] $db_bin/$sql -h $IP -U esrep -d esrep -p $db_port  -c \"select * from pg_drop_replication_slot('$slot_name');\""
    $db_bin/$sql -h $IP -U esrep -d esrep -p $db_port -c "select * from pg_drop_replication_slot('$slot_name');"
    RETVAL=$?
    check_res $RETVAL
}

function change_standby_repmgr_conf()
{
    cp_conf
    conf_name="$repmgr_conf"
    parameter="node_id='$node_id'"
    change_or_add_parm
    parameter="node_name='$node_name'"
    change_or_add_parm
    parameter="conninfo='$conninfo'"
    change_or_add_parm
    parameter="net_device='$dev'"
    change_or_add_parm
    parameter="net_device_ip='$net_device_ip'"
    change_or_add_parm
}

function create_primary_node()
{
    set_pass
    startdb
    create_superuser
    register_primary
}

function create_standby_node()
{
    change_standby_repmgr_conf
    clone_standby
    startdb
    register_standby
}

function create_witness_node()
{
    set_pass_witness
    startdb
    create_witness_superuser
    register_witness
}

function drop_standby_node()
{
    unregister_standby
    sshstopdb
    drop_standby_slot
}

function drop_witness_node()
{
    unregister_witness
    sshstopwitness
}

function clear_node()
{
    local has_data=0
    local has_repmgr=0
    local db_is_running=0
    local all_tmp_ip=(${all_ip[@]})
    local node_type="standby"

    [ "$data_path"x != ""x ] && [ -d "$data_path" ] && has_data=1
    [ "$repmgr_conf"x != ""x ] && [ -f "$repmgr_conf" ] && has_repmgr=1
    [ ${#all_tmp_ip[@]} -eq 1 ] && node_type="primary"

    if [ $has_data -eq 1 ]
    then
        $db_bin/$ctl -D $data_path status >/dev/null && db_is_running=1
        [ "${node_type}"x = "standby"x ] && [ ! -f $data_path/standby.signal ] && node_type="witness"

        if [ $db_is_running -eq 1 ]
        then
            if [ $has_repmgr -eq 1 ]
            then
                # then standby/witness DB is running, try to unregister
                [ "${node_type}"x != "primary"x ] && $db_bin/repmgr ${node_type} unregister

                # stop db and repmgrd/kbha
                $db_bin/sys_monitor.sh stoplocal 2>/dev/null
            else
                # stop db
                $db_bin/$ctl stop -w -t 90 -D $data_path
            fi
        fi

        # remove the waldir
        [ -L $data_path/sys_wal ] && /bin/rm -rf $(readlink $data_path/sys_wal)
        # remove the data_path
        /bin/rm -rf $data_path
    fi

    [ $has_repmgr -eq 1 ] && /bin/rm -f $repmgr_conf
}

function get_contrl () {
	export LC_ALL="C"

	${db_bin}/sys_controldata -D ${data_path} | grep -w -E "sys_control last modified|REDO|TimeLineID|NextXID|NextOID|oldestXID:|Time of"
}


case $function_name in
    "initdb")
        initdb
        exit 0
        ;;
    "change_or_add_parm")
        change_or_add_parm
        exit 0
        ;;
    "create_primary_node")
        create_primary_node
        exit 0
        ;;
    "create_standby_node")
        create_standby_node
        exit 0
        ;;
    "create_witness_node")
        create_witness_node
        exit 0
        ;;
    "drop_standby_node")
        drop_standby_node
        exit 0
        ;;
    "drop_witness_node")
        drop_witness_node
        exit 0
        ;;
    "check_system")
        check_system
        exit 0
        ;;
    "change_system")
        change_system
        exit 0
        ;;
    "stop_firewalld")
        stop_firewalld
        exit 0
        ;;
    "clear_node")
        clear_node
        exit 0
        ;;
	"stopdb")
        stopdb
        exit 0
        ;;
	"startdb")
		startdb
		exit 0
		;;
	"get_contrl")
		get_contrl
		exit 0
		;;
    *)
        echo "[`date`] [ERROR] incorrect function name"
        exit 66
esac

