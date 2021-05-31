# Create postgres cluster and use custom docker image for this

### 1. Build and push docker image

* First of all you need to build this image. I've provide docker image for this purpose, it should work fine on any system. The only problem - building time. Image building consists from several stage: plv8builder, pgroutingBuilder, libsBuilder, boostBuilder and final stage - the main one. Some of these stage can take a lot of time - near 1 hr. On digital ocean droplet you provide for me - libsBuilder stage take more that 50 minutes. Because of this I recommend to build these "long-lasting" stages as separate image and then just call them during building main docker image. This will save a lot of time during future builds.

    Build docker image: 

        docker build -t <goat-crunchy-image-name:centos7-12.5-3.0-4.5.1> -f Crunchy.Dockerfile . 

    Push it to your docker registry: 

        docker push <goat-crunchy-image-name:centos7-12.5-3.0-4.5.1>

* Please note that the docker image tag can be changed to any other. There should be no problems with changing the image tag, as version-dependent tools images will take the correct version from the postgres operator.

### 2. Install postgres operator and deploy it to kubernetes cluster.

* Deploy operator to cluster

    ```
        kubectl create namespace pgo
        kubectl apply -f https://raw.githubusercontent.com/CrunchyData/postgres-operator/v4.5.1/installers/kubectl/postgres-operator.yml
    ```
    After few minutes you see something like this
    ```
        NAME                                 READY   STATUS      RESTARTS   AGE
        pgo-deploy-dlb2r                     0/1     Completed   0          46m
        postgres-operator-5476fdbfbf-ctg7z   4/4     Running     0          45m
    ```
    Install operator:

    ```  
        curl https://raw.githubusercontent.com/CrunchyData/postgres-operator/v4.5.1/installers/kubectl/client-setup.sh > client-setup.sh 
        chmod +x client-setup.sh
        ./client-setup.sh

        export PGOUSER="${HOME?}/.pgo/pgo/pgouser"
        export PGO_CA_CERT="${HOME?}/.pgo/pgo/client.crt"
        export PGO_CLIENT_CERT="${HOME?}/.pgo/pgo/client.crt"
        export PGO_CLIENT_KEY="${HOME?}/.pgo/pgo/client.key"
        export PGO_APISERVER_URL='https://127.0.0.1:8443'
        export PGO_NAMESPACE=pgo
        export PATH=$PATH:/home/username/.pgo/pgo

        # or you can add this permanently to bashrc file
        
        cat <<EOF >> ~/.bashrc 
        export PGOUSER="${HOME?}/.pgo/pgo/pgouser"
        export PGO_CA_CERT="${HOME?}/.pgo/pgo/client.crt"
        export PGO_CLIENT_CERT="${HOME?}/.pgo/pgo/client.crt"
        export PGO_CLIENT_KEY="${HOME?}/.pgo/pgo/client.key"
        export PGO_APISERVER_URL='https://127.0.0.1:8443'
        export PGO_NAMESPACE=pgo
        export PATH=$PATH:/home/username/.pgo/pgo
        EOF
        source ~/.bashrc
        
        For Mac users use ~/.bash_profile instead of ~/.bashrc
    ```

    In order to communicate with Kubernetes cluster using crunchy operator you should set up port forwarding, so from another terminal paste following command:
    ```
        kubectl -n pgo port-forward svc/postgres-operator 8443:8443
    ```

    After that you can test connection:
    ```
        pgo version
    ```
    As a response you should see:
    ```
        pgo client version 4.5.1
        pgo-apiserver version 4.5.1  
    ```
* Create custom configmap. 
    In order to customize `postgresql.conf`, `pg_hba`, `setup.sql` file you need to create configmap with these configurations.  [custom-config/postgres-ha.yaml](custom-config/postgres-ha.yaml) file contain configuration that you had previously, setup.sql contains sql scripts to create extensions. I did not add any configurations related to pg_hba conf as you had previously because crunchy image already contains these configurations.

    To create configmap:
    ```
        kubectl create configmap -n pgo <clustername>-custom-pg-config --from-file=config-files/
    ```
* Final steps - deploy postgres cluster and create user

    ```
        pgo create cluster <cluster-name> --ccp-image-tag <docker_image_tag> --ccp-image <docker_image_name> --ccp-image-prefix <docker-registry-url>/<docker-registry-repo-name> --custom-config <clustername>-custom-pg-config
    ```
    Example:
    ```
        pgo create cluster goat-crunchy-cluster --ccp-image-tag centos7-12.5-3.0-4.5.1 --ccp-image goat-crunchy-image --ccp-image-prefix docker.io/goatcommunity --custom-config goat-custom-pg-config
    ```

    User creating:
    ```
        pgo create user <cluster-name>  --username <username> --password <password>
    ```
    Without setting `--password` flag it will be set automatically

    After few minutes (1-2) postgres cluster will be created in `pgo` namespace. How to be sure that cluster is created? After executing ` kubectl get pods -n pgo` you should see something like this

    ` <cluster_name>-<random alphanumberical set>-<another set>                        1/1     Running     0          3m5s `

    Example

    ` goat-5d7c697647-qwv9f                        1/1     Running     0          3m5s `

    Great! After that message you can connect to database. You need to set port forwarding to postgres service. 

    ` kubectl -n pgo port-forward svc/<cluster name> 5432:5432 `

    Connect to database with user you created previously:

    ` psql -h localhost -U <user> -d <database name>`

* spaces.yml and db.yaml files:

    This files are injected into database pod through custom configmap mentioned earlier. They will be encrypted by Mozilla SOPS in future update. 

    Their location in pod: `/pgconf`.


* Database scaling
    Scaling of postgres pods by crunchy operator is a pretty simple, the only think you need - tell postgres operator which cluster should be scaled: 
    
    ` pgo scale <cluster-name> `

    It will create read-only replica based on you primary pod. Also, you can set replica count with `--replica-count`, for example:
    
    ` pgo scale goat --replica-count 5`

    This command will create 5 read only replicas. To check availability of these replicas and primapy test use the following command:

    `pgo test goat`

    As a result you should see something like this: 

    ```
        cluster : goat
            Services
                primary (10.103.2.57:5432): UP
                replica (10.108.222.88:5432): UP
            Instances
                primary (goat-5d7c697647-qwv9f): UP
                replica (goat-bafd-575d56d496-t9k8m): UP
                replica (goat-bfad-bc645c66b-7784x): UP
                replica (goat-ljgl-54ccf45d6-79x2l): UP
                replica (goat-utmq-5ff4b4cdb4-c25jl): UP
                replica (goat-xndh-75f66bb7bc-m5znl): UP
    ```
    To scale down replica, you should use... `scaledown` command.
    First of all you need to use `pgo scaledown goat --query` to get replicas names. For some reasons you couldn't use replicas names from `pgo test goat` result. It require "short" name - `<cluster name>-<first random alphanumberical set>`. What I mean: you can’t use `goat-bafd-575d56d496-t9k8m` to delete replica using `pgo scaledown`, you need to use `goat-bafd` as replica name.

    Scale down example:
    ```
        pgo scaledown goat --target goat-bafd
    ```
    After execution replica will be deleted from cluster. IF you manually delete it using `kubectl delete pod goat-bafd-575d56d496-t9k8m` - postgres operator automatically recreate it from backup. 

    *** Important note: when you run ` pgo scale goat` - crunchy operator will create replica from latest taken backup. So it make sense to take backup before scaling.

* Backup and restore.
    Backups from database can be taken by different ways: the simple `pg_dump` execution, through the crunchy operator or using any other way.
    Backups from crunchy operator can be taken to local storage or to any s3-compatible storage ( AWS S3, DO Space and other).
    Full backup is taken automatically after create postgres cluster, and future backups will be taken in incremental node ( to previous backup will be added only difference between current and previous state).

    To perform backup which will be stored to s3 storage, cluster should be configured to use s3 as storage type for backups. It needs to be configured during creating, because after creating it can't be changed:
    
    AWS example:
     
    ```
        pgo create cluster aws-goat-cluster --pgbackrest-s3-bucket <aws s3 bucket name> \
        --pgbackrest-s3-endpoint s3.amazonaws.com \
        --pgbackrest-s3-key <AWS_KEY_ID> \
        --pgbackrest-s3-key-secret <AWS_KEY_SECRET> \
        --pgbackrest-s3-region <aws s3 region> \
        --pgbackrest-s3-uri-style host \
        --pgbackrest-storage-type s3 \
        --ccp-image-tag centos7-12.5-3.0-4.5.1 \
        --ccp-image goat-crunchy-image \
        --ccp-image-prefix docker.io/goatcommunity
    ```

    Digital Ocean example:

    ```
        pgo create cluster do-goat-cluster --pgbackrest-s3-verify-tls=false \
        --pgbackrest-s3-bucket < DO space name > \
        --pgbackrest-s3-endpoint fra1.digitaloceanspaces.com \
        --pgbackrest-s3-region fra1 \
        --pgbackrest-s3-uri-style path \
        --pgbackrest-s3-key < SPACES KEY ID> \
        --pgbackrest-s3-key-secret < SPACES KEY SECRET> \
        --pgbackrest-storage-type s3 \
        --ccp-image-tag centos7-12.5-3.0-4.5.1 \
        --ccp-image goat-crunchy-image \
        --ccp-image-prefix docker.io/goatcommunity
    ```

    When you are using aws s3 bucket you need to specify `--pgbackrest-s3-region` option. AWS S3 not attached to any region unlike many other services, so you can specify any region, for example - `us-east-2`
    Also there is option `--pgbackrest-s3-uri-style` which will have different values for DO and AWS s3 storages.

    After a while cluster will be created and you will see folder with backup taken by crunchy operator in your S3 storage:
    
    DO:
    ![alt text](http://img.empeek.net/1IPAMAU.png)

    ![alt text](http://img.empeek.net/1IPAK0N.png)

    AWS:
    ![alt text](http://img.empeek.net/1IPAO3M.png)

    ![alt text](http://img.empeek.net/1IPAPSZ.png)

    Please note that backup uploading to s3 storage can take a little bit more time that it extected. First backup can take more than 5 minutes, the following backups can be taken in incremental time, so uploading time depend on data amount.

    Database restore can be taken in similar way:

    ```
        pgo create cluster aws-goat-cluster --restore-from aws-goat-cluster-old \
        --restore-opts="--repo-type=s3" \
        --pgbackrest-s3-bucket <aws s3 bucket name> \
        --pgbackrest-s3-endpoint s3.amazonaws.com \
        --pgbackrest-s3-key <AWS_KEY_ID> \
        --pgbackrest-s3-key-secret <AWS_KEY_SECRET> \
        --pgbackrest-s3-region <aws s3 region> \
        --pgbackrest-s3-uri-style host \
        --pgbackrest-storage-type s3 \
        --ccp-image-tag centos7-12.5-3.0-4.5.1 \
        --ccp-image goat-crunchy-image \
        --ccp-image-prefix docker.io/goatcommunity
    ```

    After this, crunchy operator download backup from s3 storage and then, using pgbackrest create new cluster based on backup.
    Also you can just restore cluster from backup without creating the new one:
    `pgo restore cluster goat-cluster`.

    Be aware! This command is a destructive and destroy existing cluster and recreate it.

* Data persistence
    By default postgres operator create volume where data is stored. So, if something will happened with database pod and it will be recreated - data will be restored too. The only problems that can appear - unfinished transtactions during pod crash.

* Fault tolerance
    To enable fault tolerance you need to have at least one replica, so the first step should be: 
    
        pgo scale goat --replica-count 5

    Test the cluster:

        cluster : goat
	    Services
            primary (10.108.37.227:5432): UP
            replica (10.110.195.230:5432): UP
	    Instances
            primary (goat-5f8b6d5ff6-zkt98): UP
            replica (goat-orgm-845cb77846-55wh2): UP

    In the case where the primary is down, the first replica to notice this starts an election. Per the Raft algorithm, each available replica compares which one has the latest changes available, based upon the LSN of the latest logs received. The replica with the latest LSN wins and receives the vote of the other replica. The replica with the majority of the votes wins. In the event that two replicas’ logs have the same LSN, the tie goes to the replica that initiated the voting request.
    Once an election is decided, the winning replica is immediately promoted to be a primary and takes a new lock in the distributed etcd cluster. If the new primary has not finished replaying all of its transactions logs, it must do so in order to reach the desired state based on the LSN. Once the logs are finished being replayed, the primary is able to accept new queries.
    So, to test this feature lets kill primary prod: 
        
        kubectl delete pod -n pgo goat-5f8b6d5ff6-zkt98 

    And test cluster again:

        pgo test goat

        cluster : goat
	    Services
            primary (10.108.37.227:5432): UP
            replica (10.110.195.230:5432): UP
	    Instances
            replica (goat-5f8b6d5ff6-d75h7): UP
            primary (goat-orgm-845cb77846-55wh2): UP

    We can see that replica became primary after deleting primary pod and new replica was created instead previous one.
    It more preferable to have more that one replica, because if a replica believes that a primary is down and starts an election, but the primary is actually not down, the replica will not receive enough votes to become a new primary and will go back to following and replaying the changes from the primary.

* TLS configuration
    To enale TLS in your Postgresql Clusters you need: `CA certificate`, `TLS private key`, `TLS certificate`

    I will show how to create and use for enabling tls configuration, but you can test your own certificates and keys.

    We first need to generate a CA:

        openssl req \
            -x509 \
            -nodes \
            -newkey ec \
            -pkeyopt ec_paramgen_curve:prime256v1 \
            -pkeyopt ec_param_enc:named_curve \
            -sha384 \
            -keyout ca.key \
            -out ca.crt \
            -days 3650 \
            -subj "/CN=*"

    Then wee need to generate TLS key and certificate or cluster.
    We will create cluster goat in namespace pgo, so CN for out certs will be `goat.gpo`:

        openssl req \
            -new \
            -newkey ec \
            -nodes \
            -pkeyopt ec_paramgen_curve:prime256v1 \
            -pkeyopt ec_param_enc:named_curve \
            -sha384 \
            -keyout server.key \
            -out server.csr \
            -days 365 \
            -subj "/CN=goat.pgo"
    
    And finally sign CA: 

        openssl x509 \
            -req \
            -in server.csr \
            -days 365 \
            -CA ca.crt \
            -CAkey ca.key \
            -CAcreateserial \
            -sha384 \
            -out server.crt

    Now we can create cluster with TLS enabled:
    1. Create secrets for postgres cluster ( secrets should be in same namespace as where we deploying our cluster, name of key that is holding the CA must be `ca.crt`)
            
            kubectl create secret generic postgresql-ca -n pgo --from-file=ca.crt=ca.crt
            kubectl create secret tls goat.tls -n pgo --cert=server.crt --key=server.key
        
    2. With these secrets we can create cluster now:

            pgo create cluster goat --server-ca-secret=postgresql-ca
                --server-tls-secret=goat.tls  
                --ccp-image-tag centos7-12.5-3.0-4.5.1 \
                --ccp-image goat-crunchy-image \
                --ccp-image-prefix docker.io/goatcommunity

        To force tls usage use `--tls-only` option:

             pgo create cluster goat --tls-only
                --server-ca-secret=postgresql-ca
                --server-tls-secret=goat.tls  
                --ccp-image-tag centos7-12.5-3.0-4.5.1 \
                --ccp-image goat-crunchy-image \
                --ccp-image-prefix docker.io/goatcommunity

    3. Create user:

            pgo create user goat  --username goat --password mysecretpassword1

    4. Lets connect to database without ssl usage:

            kubectl -n pgo port-forward svc/hippo 5432:5432

            PGSSLMODE=disable PGPASS=mysecretpassword1 psql -h localhost -U devops postgres

        After this you will error:

            psql: FATAL:  no pg_hba.conf entry for host "127.0.0.1", user "devops", database "devops", SSL off

    5. Now lets try to connect with sll enabled:

            PGSSLMODE=require PGPASS=mysecretpassword1 psql -h localhost -U devops postgres

        And.. It connected successfully!

    More detailed about ssl configuration you can read [here](https://blog.crunchydata.com/blog/set-up-tls-for-postgresql-in-kubernetes)




            
    


