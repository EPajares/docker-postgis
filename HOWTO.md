# Create postgres cluster and use custom docker image for this

### 1. Build and push docker image

* First of all you need to build this image. I've provide docker image for this purpose, it should work fine on any system. The only problem - building time. Image building consist from several stage: plv8builder, pgroutingBuilder, libsBuilder, boostBuilder and final stage - the main one. Some of these stage can take a lot of time - near 1 hr. On digital ocean droplet you provide for me - libsBuilder stage take more that 50 minutes. Because of this I recomment to build these "long-lasting" stages as separate image and then just call them during buildin main docker image. This will save a lot of time during future builds.

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


    


