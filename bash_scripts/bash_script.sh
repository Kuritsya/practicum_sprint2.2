#!/usr/bin/bash

show_help() {
    cat << EOF
Использование: $(basename "$0") [ОПЦИИ]

Скрипт для отображения информации о системе

Опции:
  --help		Информация о том, какие параметры поддерживает скрипт и что они значат
  --host		Информацию о хосте
  --user		Информация о пользователях
EOF
}

function get_cpu_cores_info {
    cores=$(grep -c '^processor' /proc/cpuinfo)
    
	echo "--- Информация о CPU ---"
	echo "Ядер CPU: $cores"
}

function get_RAM_info {
    clear_RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    clear_available_RAM=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    
    used_RAM=$((clear_RAM - clear_available_RAM))
    
    total_RAM=$(awk "BEGIN {printf \"%.2f\", $clear_RAM / 1024 / 1024}")
    total_used_RAM=$(awk "BEGIN {printf \"%.2f\", $used_RAM / 1024 / 1024}")
    
    echo "--- Информация о RAM ---"
    echo "Всего RAM: $total_RAM GB"
    echo "Занято RAM: $total_used_RAM GB"
}

function get_disk_info {
    echo "--- Информация о дисках ---"

    printf "%-12s %-10s %-10s %-12s %-10s\n" "Устройство" "Размер" "Свободно" "Свободно %" "Ошибки"
    printf "%-12s %-10s %-10s %-12s %-10s\n" "----------" "------" "--------" "----------" "----------"
	
    disks=$(awk '{print $3}' /proc/diskstats | grep -E '^([sh]d[a-z]|nvme[0-9]n[0-9])$' | sort -u)
	
    if [ -z "$disks" ]; then
        disks=$(df --output=source | grep '^/dev/' | sed 's|/dev/||' | sort -u)
    fi
	
    for dev in $disks; do
        disk_df_line=$(df -h | grep "/dev/${dev}" | head -n 1)

        disk_size="-"
        disk_free="-"
        disk_free_pct="-"
        disk_errors="0"

        if [ -n "$disk_df_line" ]; then
            disk_size=$(echo "$disk_df_line" | awk '{print $2}')
            disk_free=$(echo "$disk_df_line" | awk '{print $4}')
            disk_used_pct=$(echo "$disk_df_line" | awk '{print $5}' | tr -d '%')
            
            if [[ "$disk_used_pct" =~ ^[0-9]+$ ]]; then
                disk_free_pct="$((100 - disk_used_pct))%"
            fi
        fi

        printf "%-12s %-10s %-10s %-12s %-10s\n" "/dev/$dev" "$disk_size" "$disk_free" "$disk_free_pct" "$disk_errors"
    done
}

function get_system_load_average_info {
	load_average=$(cat /proc/loadavg)
	
	read -r avg_1 avg_5 avg_15 rest <<< "$load_average"
	
	echo "--- Средняя загрузка системы ---"
    echo "За 1 мин:  $avg_1"
    echo "За 5 мин:  $avg_5"
    echo "За 15 мин: $avg_15"
}

function get_now_info {
	datetime=$(date)
	
	read -r week_day month day time PM_AM time_zone year rest <<< "$datetime"
	
	echo "--- Текущее время в системе ---"
    echo "$day $month $year  $time $PM_AM $time_zone"
}


function get_system_uptime_info {
    system_uptime=$(cat /proc/uptime)
	
    read -r raw_uptime_sec _ <<< "$system_uptime"
	
    uptime_sec=${raw_uptime_sec%.*}
	
    days=$(( uptime_sec / 86400 ))
    hours=$(( (uptime_sec % 86400) / 3600 ))
    mins=$(( (uptime_sec % 3600) / 60 ))
    secs=$(( uptime_sec % 60 ))
	
    echo "--- Время работы системы ---"
    
    if [ "$days" -gt 0 ]; then
        echo "$days дн $hours ч $mins мин $secs сек"
    else
        echo "$hours ч $mins мин $secs сек"
    fi
}

function get_network_interfaces_info {
	echo "--- Информация о сетевых интерфейсах ---"
	
	printf "%-10s %-8s %-16s %-12s %-12s %-8s\n" "Интерфейс" "Статус" "IP-адрес" "Получатель" "Отправитель" "Ошибки"
    printf "%-10s %-8s %-16s %-12s %-12s %-8s\n" "----------" "------" "----------------" "------------" "------------" "------"

    while read -r line; do
        [[ "$line" =~ (Inter-|face) ]] && continue

        iface=$(echo "$line" | cut -d: -f1 | xargs)
        [ -z "$iface" ] && continue

        stats=$(echo "$line" | cut -d: -f2)

        rx_packets=$(echo "$stats" | awk '{print $2}')
        rx_errors=$(echo "$stats" | awk '{print $3}')
        tx_packets=$(echo "$stats" | awk '{print $10}')
        tx_errors=$(echo "$stats" | awk '{print $11}')
        
        total_errors=$((rx_errors + tx_errors))

        status="DOWN"
        if [ -f "/sys/class/net/${iface}/operstate" ]; then
            status=$(cat "/sys/class/net/${iface}/operstate" | tr '[:lower:]' '[:upper:]')
        fi

        ip_addr=$(ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
        
        [ -z "$ip_addr" ] && ip_addr="-"

        printf "%-10s %-8s %-16s %-12s %-12s %-8s\n" "$iface" "$status" "$ip_addr" "$rx_packets" "$tx_packets" "$total_errors"

    done < /proc/net/dev
}

function get_listening_ports_info {
	echo "--- Слушающие сетевые порты ---"
	
	printf "%-10s %-22s %-10s\n" "Протокол" "Порт" "Статус"
    printf "%-10s %-22s %-10s\n" "--------" "--------------------" "------"

    if command -v ss &> /dev/null; then
        ss -lntu | awk 'NR>1 {print $1, $5, "LISTEN"}' | while read -r proto addr state; do
            printf "%-10s %-22s %-10s\n" "${proto^^}" "$addr" "$state"
        done
    elif command -v netstat &> /dev/null; then
        netstat -lntu | awk 'NR>2 {print $1, $4, $6==""?"LISTEN":$6}' | while read -r proto addr state; do
            printf "%-10s %-22s %-10s\n" "${proto^^}" "$addr" "$state"
        done
    else
        echo "Ошибка: утилиты 'ss' и 'netstat' не найдены в системе."
    fi
}

function get_all_users_info {
	echo -e "--- Все пользователи в системе ---"
    real_users=""
    system_users=""

    while IFS=: read -r username _ uid _ _ _ _; do
        if [ "$uid" -ge 1000 ] || [ "$uid" -eq 0 ]; then
            real_users+="$username, "
        else
            system_users+="$username, "
        fi
    done < /etc/passwd

    echo "Реальные:  ${real_users%, }"
    echo "Системные: ${system_users%, }"
}

function get_root_users_info {
	echo -e "--- Пользователи с правами Root ---"
    root_users=""

    while IFS=: read -r username _ uid _ _ _ _; do
        if [ "$uid" -eq 0 ]; then
            root_users+="$username, "
        fi
    done < /etc/passwd

    echo "Аккаунты c Root правами: ${root_users%, }"
}

function get_login_users_info {
	echo -e "--- Залогиненные пользователи ---"
    
    if [ -z "$(who)" ]; then
        echo "В сети нет активных пользователей"
        return
    fi

    printf "%-12s %-10s %-16s %-10s\n" "Пользователь" "Терминал" "Время входа" "IP-адрес"
    printf "%-12s %-10s %-16s %-10s\n" "------------" "--------" "-----------" "--------"

    who | while read -r user tty date time ip; do
        clean_ip=$(echo "$ip" | tr -d '()')
        [ -z "$clean_ip" ] && clean_ip="локально"

        printf "%-12s %-10s %-16s %-10s\n" "$user" "$tty" "$date $time" "$clean_ip"
    done
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

PARSED_OPTIONS=$(getopt -o h --long help,host,user -- "$@")
if [ $? -ne 0 ]; then
    echo "Используйте $(basename "$0") --help для справки." >&2
    exit 1
fi

eval set -- "$PARSED_OPTIONS"

RUN_HELP=false
RUN_HOST=false
RUN_USER=false

while true; do
    case "$1" in
        -h|--help)
            RUN_HELP=true
            shift
            ;;
        --host)
            RUN_HOST=true
            shift
            ;;
        --user)
            RUN_USER=true
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Неизвестный параметр: $1" >&2
            exit 1
            ;;
    esac
done

if [ "$RUN_HELP" = true ]; then
    show_help
fi

if [ "$RUN_HOST" = true ]; then
    get_cpu_cores_info
    get_RAM_info
    get_disk_info
    get_system_load_average_info
    get_now_info
    get_system_uptime_info
    get_network_interfaces_info
    get_listening_ports_info
fi

if [ "$RUN_USER" = true ]; then
    get_all_users_info
    get_root_users_info
    get_login_users_info
fi
