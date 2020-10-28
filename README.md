# Setup master-slave replication between two mysql docker containers. (MYSQL Version 8.0)

To run:
  - Install docker (check the doc [here](https://docs.docker.com/engine/install/))
  - Clone this repo
  - Execute the following commands in terminal
    ```sh
    $ cd mysql_replication
    $ chmod 777 script.sh
    $ ./script.sh
    ```
### Caveat
This script works as if it's running the entire setup for the first time. If docker-compose fails to create the containers, please uncomment `line 7` in script.sh
