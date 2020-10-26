#!/bin/bash
BASE_PATH=$(dirname $0)
PRIMARY_HOST=''
LOG_FILE=''
LOG_POS=''

docker-compose down
docker-compose up -d

containers=(primary secondary)
for ((i=0; i<${#containers[@]}; ++i)); do
    echo -ne "\033[0;36mConfiguring ${containers[$i]} ... "
    docker exec -i ${containers[$i]} bash -c 'echo "log-bin=mysql-bin" >> /etc/my.cnf'
    echo 'echo server-id='"$[i+1]"' >> /etc/my.cnf' | xargs -I {} docker exec -i ${containers[$i]} bash -c {}
    echo -ne "done\033[0;39m"
    echo
done

docker-compose restart primary

PRIMARY_HOST=$(docker exec -it primary bash -c "cat /etc/hosts" | grep primary | awk '{print $1;}')
sleep 2
echo -ne "\033[0;36mPRIMARY HOST: $PRIMARY_HOST\033[0;39m"
echo

until docker exec -it primary bash -c "mysql -uroot --password=password -AN -e \"CREATE USER 'repl'@'%' IDENTIFIED WITH 'mysql_native_password' BY 'password';\" 2>/dev/null"; do
    sleep 1
done
until docker exec -it primary bash -c "mysql -uroot --password=password -AN -e \"GRANT SELECT, PROCESS, FILE, SUPER, REPLICATION CLIENT, REPLICATION SLAVE, RELOAD ON *.* TO 'repl'@'%';\" 2>/dev/null"; do
    sleep 1
done
until docker exec -it primary bash -c "mysql -uroot --password=password -AN -e \"FLUSH PRIVILEGES;\" 2>/dev/null"; do
    sleep 1
done
until docker exec -it primary bash -c "mysql -uroot --password=password -AN -e \"FLUSH LOGS;\" 2>/dev/null"; do
    sleep 1
done
echo -ne "\033[0;36mPrimary configuration done.\033[0;39m"
echo
LOG_FILE=$(docker exec -it primary bash -c "mysql -uroot --password=password -e 'SHOW MASTER STATUS \G;'" | grep File | awk '{print $2;}')
LOG_POS=$(docker exec -it primary bash -c "mysql -uroot --password=password -e 'SHOW MASTER STATUS \G;'" | grep Position | awk '{print $2;}')
# docker exec -it primary bash -c "mysql -uroot --password=password -e 'SHOW MASTER STATUS \G;' 2>/dev/null"

docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"STOP SLAVE;\" 2>/dev/null";
docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"STOP SLAVE IO_THREAD FOR CHANNEL '';\" 2>/dev/null";
docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"CHANGE MASTER TO MASTER_HOST='$PRIMARY_HOST';\" 2>/dev/null";
docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"CHANGE MASTER TO MASTER_PORT=3306;\" 2>/dev/null";
docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"CHANGE MASTER TO MASTER_USER='repl';\" 2>/dev/null";
docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"CHANGE MASTER TO MASTER_PASSWORD='password';\" 2>/dev/null";
# The below doesn't work. So commenting it out to 
# docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"CHANGE MASTER TO MASTER_LOG_FILE='$LOG_FILE';\" 2>/dev/null";
# docker exec -it secondary bash -c "mysql -uroot --password=password -AN -e \"CHANGE MASTER TO MASTER_LOG_POS=$LOG_POS;\" 2>/dev/null";

docker-compose restart secondary

until docker exec -it secondary bash -c "mysql -uroot --password=password -e 'SHOW SlAVE STATUS \G;' &> /dev/null"; do
    sleep 1
done
STATUS=$(docker exec -it secondary bash -c "mysql -uroot --password=password -e 'SHOW SlAVE STATUS \G;' 2>/dev/null")
SIOR=$(echo $STATUS | grep Slave_IO_Running: | awk '{print $2;}')
SSQLR=$(echo $STATUS | grep Slave_SQL_Running:  | awk '{print $2;}')
if [ ! $SIOR -o ! $SSQLR  ]; then
    echo "Some thing went wrong during the setup"
    exit 1
else
    echo -ne "\033[0;36mContainers setup complete \033[0;39m"
fi
echo
sleep 2

echo -ne "\033[0;36mTesting replication ... \033[0;39m"
docker exec -it primary bash -c "mysql -uroot --password=password -e 'CREATE DATABASE REPL_TEST;' 2>/dev/null"
REPL_DB=$(docker exec -it secondary bash -c "mysql -uroot --password=password -e 'SHOW DATABASES;' 2>/dev/null" | grep REPL_TEST | awk '{print $2;}')
if [[ $REPL_DB ]];then
    echo -ne "\033[0;36msuccess\033[0;39m"
else
    echo -ne "\033[0;31mfailed\033[0;39m"
fi
echo