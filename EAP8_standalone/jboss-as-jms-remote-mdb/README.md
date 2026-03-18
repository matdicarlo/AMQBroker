**Very simple example of MDB listening on a remote destination hosted in AMQ 7.8 external broker**

**Description**
 - This is a simple example of a MDB that listens on a remote destiation hosted by a remote AMQ 7.8 broker. The project uses Artemis Resource Adadapter to connect to remote queues and exteranl JNDI context to lookup all requred resoruce in remote EAP instances.

**Requirements**

 - JBoss EAP 7.4 intances or later
 - AMQ 7.8 broker or later

**Steps to deploy the example**

- create JBoss EAP MDB hosting instance

  - `cp $JBOSS_HOME`
  - add a EAP user `quickuser`
    - `./add-user.sh -a -u quickuser -p quick123+ -g guest`
  - start the instance
    - `$JBOSS_HOME/standalone.sh`
  - creat AMQ resources 
    - `./jboss-cli.sh --connect --file=external-ra.cli`
  - created AMQ 7 broker 
    - `cd $AMQ_HOME/bin` 
    - `./artemis create --user quickuser --password quick123+ --require-login  --queues inQueue ../test`
    - `cd ../test/bin`
    - `./artermis run`
    
- build and deploy the proejct
  - `cd ${project root directory}`
  - `mvn clean package wildfly:deploy`


TODO

