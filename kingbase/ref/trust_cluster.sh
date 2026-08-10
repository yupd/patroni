#!/bin/bash

# you should change two parameters: general_user and all_ip
# general_user is the general user which you want to config SSH password free
# all_ip is the devices that you want to config SSH password free

shell_folder=$(dirname $(readlink -f "$0"))
install_conf="${shell_folder}/install.conf"

curren_user=`whoami`
execute_user="kingbase"
super_user="root"
binary_remote="ssh"
binary_local="ssh"
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

function execute_command()
{
    local user=$1
    local host=$2
    local command=$3
    local command_options="-q -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p ${ssh_port}"
    ssh ${command_options} -l ${user} -T $host "${command}"
    [ $? -ne 0 ] && return 1
    return 0
}
function test_connect()
{
    local ip1="$1"
    local ip2="$2"

    [ "$ip1"x = ""x -a "$ip2"x = ""x ] && return 0

    # binary_local and binary_remote is set in pre_exe()
    if [ "$ip2"x = ""x ]
    then
        $binary_local ${command_options} -l ${super_user} -T $ip1 "/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null"
        local super_bin_ret=$?
        $binary_local ${command_options} -l ${execute_user} -T $ip1 "/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null"
        local exe_bin_ret=$?
        if [ "$super_bin_ret"x == "0"x -a "$exe_bin_ret"x == "0"x ]
        then
           echo "connect to \"${ip1}\" from current node by '${binary_local}' root:${super_bin_ret} kingbase:${exe_bin_ret}..... OK"
           return 0
        else
           echo "connect to \"${ip1}\" from current node by '${binary_local}' root:${super_bin_ret} kingbase:${exe_bin_ret}..... FAIL"
           return 1
        fi
    else
        $binary_local ${command_options} -l ${super_user} -T $ip1 "$binary_remote ${scmd_options} -l ${super_user} -T $ip2 \"/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null\""
        local su_su_bin_ret=$?
        $binary_local ${command_options} -l ${execute_user} -T $ip1 "$binary_remote ${scmd_options} -l ${execute_user} -T $ip2 \"/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null\""
        local exe_exe_bin_ret=$?
        $binary_local ${command_options} -l ${super_user} -T $ip1 "$binary_remote ${scmd_options} -l ${execute_user} -T $ip2 \"/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null\""
        local su_exe_bin_ret=$?
        $binary_local ${command_options} -l ${execute_user} -T $ip1 "$binary_remote ${scmd_options} -l ${super_user} -T $ip2 \"/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null\""
        local exe_su_bin_ret=$?
        if [ "$su_su_bin_ret"x == "0"x -a "$exe_exe_bin_ret"x == "0"x -a "$su_exe_bin_ret"x == "0"x -a "$exe_su_bin_ret"x == "0"x ]
        then
            echo "connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}' ${super_user}->${super_user}:${su_su_bin_ret} ${super_user}->${execute_user}:${su_exe_bin_ret} ${execute_user}->${execute_user}:${exe_exe_bin_ret}  ${execute_user}->${super_user}:${exe_su_bin_ret}.... OK"
            return 0
        else
            echo "connect to \"${ip2}\" from \"$ip1\" by '${binary_remote}' ${super_user}->${super_user}:${su_su_bin_ret} ${super_user}->${execute_user}:${su_exe_bin_ret} ${execute_user}->${execute_user}:${exe_exe_bin_ret}  ${execute_user}->${super_user}:${exe_su_bin_ret}.... FAIL"
            return 1
        fi
    fi
}

function check_net()
{
    local ip1=$1
    local ip2=$2
    test_connect $ip1
    if [ "$ip1"x != ""x -a "$ip2"x != ""x ]
    then
        test_connect $ip1 $ip2
    fi
}

if [ -f $install_conf ]
then
    load_conf_value_under_header $install_conf install
else
    echo "[ERROR] there is no [install.conf] found in current path"
    exit 1
fi

general_user=$execute_user
[ "${ssh_port}"x = ""x ] && ssh_port=22
if [ "${all_ip}"x = ""x ]
then
    if [ "${production_ip}"x = ""x ]
    then
        # if all_ip and production_ip both are NULL, print error message.
        echo "[ERROR] [all_ip] and [production_ip] both are empty, please check your [install.conf] file"
        exit 1
    elif [ "${local_disaster_recovery_ip}"x = ""x ]
    then
        echo "[ERROR] param [local_disaster_recovery_ip] is empty, please check your [install.conf] file"
        exit 1
    fi

    if [ ${#remote_disaster_recovery_ip[@]} -gt 1 ]
    then
        echo "[ERROR] [remote_disaster_recovery_ip] could only set one IP"
        exit 1
    fi
    all_ip=("${production_ip[@]}" "${local_disaster_recovery_ip[@]}" "${remote_disaster_recovery_ip[@]}")
fi
[ "${general_user}"x = ""x ] && echo "[ERROR] [general_user] is empty, please check your [install.conf] file" && exit 1

[ "${primary_host}"x = ""x ] && primary_host="${all_ip[0]}"

if [ "$curren_user"x != "root"x ]
then
    echo "must use root to execute"
    exit 1;
fi

[ ! -d /home/$general_user ] && /usr/sbin/adduser $general_user && echo "$general_user:123" | chpasswd
[ ! -f /home/$general_user/.ssh ] && mkdir -p /home/$general_user/.ssh

[ ! -f ~/.ssh/id_rsa.pub ] && ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa
[ ! -f  ~/.ssh/authorized_keys ] && cat ~/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

ssh -q -o Batchmode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o ServerAliveInterval=2 -o ServerAliveCountMax=5 -p 22 root@localhost "/bin/true 2>/dev/null || /usr/bin/true 2>/dev/null"
if [[ $? -ne 0 ]]; then
    ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa
    cat ~/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
fi

cp /root/.ssh/* /home/$general_user/.ssh

if [ "${witness_ip}"x != ""x ]
then
    all_ip[${#all_ip[*]}]=${witness_ip}
fi

for ips in ${all_ip[@]}
do
    [ "${primary_host}"x != ""x -a "${primary_host}"x = "${ips}"x ] && continue
    ssh -p ${ssh_port} root@$ips "test ! -f ~/.ssh/id_rsa.pub" && ssh -p ${ssh_port} root@$ips "ssh-keygen -t rsa -P \"\" -f /root/.ssh/id_rsa"
    scp -P ${ssh_port} -o StrictHostKeyChecking=no -r /root/.ssh/* root@[$ips]:/root/.ssh/
    ssh -p ${ssh_port} root@$ips "test ! -d /home/$general_user" && ssh -p ${ssh_port} root@$ips "/usr/sbin/adduser $general_user" && ssh -p ${ssh_port} root@$ips "echo \"$general_user:123\" | chpasswd"
done

for ips in ${all_ip[@]}
do
    ssh -p ${ssh_port} root@$ips "cp -r /root/.ssh /home/$general_user/"
    ssh -p ${ssh_port} root@$ips "chmod 700 /home/$general_user/.ssh/"
    ssh -p ${ssh_port} root@$ips "chown -R $general_user:$general_user /home/$general_user/.ssh/"
done

# test ssh
should_exit=0
ip_count=${#all_ip[@]}
for((i=0;i<$ip_count;i++))
do
   ip1=${all_ip[$i]}
   ip2=${all_ip[$i+1]}
   [ "$ip2"x == ""x ] && ip2=${all_ip[0]}
   check_net $ip1 $ip2
   [ $? -ne 0 ] && should_exit=1
done
if [ $should_exit -eq 0 ]
then
    echo "check ssh connection success!"
    exit 0
else
    echo "check ssh connection fail!"
    exit 1
fi
