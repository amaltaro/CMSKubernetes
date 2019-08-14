#!/bin/bash
##H Usage: deploy.sh ACTION CONFIGURATION_AREA CERTIFICATES_AREA HMAC
##H
##H Available actions:
##H   help       show this help
##H   cleanup    cleanup services
##H   create     create generic cluster with all services
##H   services   create services cluster
##H   frontend   create frontend cluster
##H   ingress    create ingress controller
##H   monitoring create monitoring components
##H   crons      create crons components
##H   secrets    create secrets files
##H   scale      scale services
##H   status     check status of the services
##H

# common defititions (adjust if necessary)
cluster=cmsweb
cluster_ns="CMS Webtools Mig"
sdir=services
mdir=monitoring
idir=ingress
cdir=crons

# services for cmsweb cluster, adjust if necessary
cmsweb_ing="ing-srv"
cmsweb_srvs="httpgo httpsgo frontend acdcserver alertscollector cmsmon confdb couchdb crabcache crabserver das dbs dqmgui phedex reqmgr2 reqmgr2ms reqmon t0_reqmon t0wmadatasvc workqueue"

# list of DBS instances
dbs_instances="default migrate global-r global-w phys03-r phys03-w"

# define help
if [ "$1" == "-h" ] || [ "$1" == "-help" ] || [ "$1" == "--help" ] || [ "$1" == "help" ]; then
    perl -ne '/^##H/ && do { s/^##H ?//; print }' < $0
    exit 1
fi
action=$1

# check status of the services
check()
{
    echo
    echo "*** check secrets"
    kubectl get secrets --all-namespaces
    echo
    echo "*** check ingress"
    kubectl get ing
    echo
    echo "*** check pods"
    kubectl get pods --all-namespaces
    echo
    echo "*** check services"
    kubectl get svc --all-namespaces
    echo
    echo "*** check cronjobs"
    kubectl get cronjobs --all-namespaces
    echo
    echo "*** check horizontal scalers"
    kubectl get hpa --all-namespaces
    echo
    echo "*** node status"
    kubectl top node
    echo
    echo "*** pods status"
    kubectl top pods
}

# verify what we should do with given action
if [ "$action" == "cleanup" ]; then
    echo "+++ perform cleanup"
elif [ "$action" == "services" ]; then
    # services for cmsweb cluster, adjust if necessary
    cmsweb_ing="ing-srv"
    cmsweb_srvs="httpgo httpsgo acdcserver alertscollector cmsmon confdb couchdb crabcache crabserver das dbs dqmgui phedex reqmgr2 reqmgr2ms reqmon t0_reqmon t0wmadatasvc workqueue"
    echo "+++ create services cluster"
elif [ "$action" == "frontend" ]; then
    # services for cmsweb-nginx cluster
    cmsweb_ing="ing-nginx"
    cmsweb_srvs="httpgo httpsgo frontend"
    echo "+++ create frontend cluster"
elif [ "$action" == "create" ]; then
    echo "+++ create generic cluster"
elif [ "$action" == "secrets" ]; then
    echo "+++ create secrets"
elif [ "$action" == "crons" ]; then
    echo "+++ create crons"
elif [ "$action" == "ingress" ]; then
    echo "+++ create ingress"
elif [ "$action" == "monitoring" ]; then
    echo "+++ create monitoring"
elif [ "$action" == "status" ]; then
    check
    exit 0
else
    perl -ne '/^##H/ && do { s/^##H ?//; print }' < $0
    exit 1
fi

if [ "$action" != "cleanup" ]; then
    conf=$2
    certificates=$3
    if [ $# -eq 4 ]; then
        hmac=$4
    else
        echo "+++ generate hmac secret"
        hmac=/tmp/$USER/hmac
        perl -e 'open(R, "< /dev/urandom") or die; sysread(R, $K, 20) or die; print $K' > $hmac
    fi
    echo "+++ perform action   : $action"
    echo "+++ use configuration: $conf"
    echo "+++ use certificates : $certificates"
    echo "+++ use hmac file    : $hmac"
fi

hname=`openstack --os-project-name "$cluster_ns" coe cluster show $cluster | grep node_addresses | awk '{print $4}' | sed -e "s,\[u',,g" -e "s,'\],,g"`
kubehost=`host $hname | awk '{print $5}' | sed -e "s,ch.,ch,g"`
echo "Kubernetes host: $kubehost"

scale()
{
    # dbs, generic scalers
    kubectl autoscale deployment dbs-migrate --cpu-percent=80 --min=2 --max=10
    kubectl autoscale deployment dbs-global-r --cpu-percent=80 --min=3 --max=10
    kubectl autoscale deployment dbs-global-w --cpu-percent=80 --min=2 --max=5
    kubectl autoscale deployment dbs-phys03-r --cpu-percent=80 --min=2 --max=4
    kubectl autoscale deployment dbs-phys03-w --cpu-percent=80 --min=2 --max=4

    kubectl apply -f crons/dbs-global-r-scaler.yaml --validate=false

    # frontend scalers
    kubectl autoscale deployment frontend --cpu-percent=80 --min=3 --max=10
    kubectl apply -f crons/frontend-scaler.yaml --validate=false

    # scalers for other cmsweb services
    for srv in $cmsweb_srvs; do
        # explicitly scaled above, we'll skip them here
        if [ "$srv" == "dbs" ] || [ "$srv" == "frontend" ]; then
            continue
        else
            # default autoscale for service
            kubectl autoscale deployment $srv --cpu-percent=80 --min=1 --max=3
        fi
    done

    kubectl get hpa
}

cleanup()
{
    # delete crons
    echo "--- delete crons"
    kubectl delete -f crons

    # delete monitoring
    echo "--- delete monitoring"
    kubectl delete -f monitoring

    # delete ingress
    echo "--- delete ingress"
    kubectl delete -f ingress/${cmsweb_ing}.yaml

    # delete secrets
    echo "--- delete secrets"
    kubectl delete secrets --all

    # delete pods
    echo "--- delete pods"
    for srv in $cmsweb_srvs; do
        # special case for DBS instances
        if [ "$srv" == "dbs" ]; then
            for inst in $dbs_instances; do
                if [ -f $sdir/${srv}-${inst}.yaml ]; then
                    kubectl delete -f $sdir/${srv}-${inst}.yaml
                fi
            done
        else
            if [ -f $sdir/${srv}.yaml ]; then
                kubectl delete -f $sdir/${srv}.yaml
            fi
        fi
    done
}

deploy_secrets()
{
    # cmsweb configuration area
    echo "+++ configuration: $conf"
    echo "+++ certificates : $certificates"

    # robot keys and cmsweb host certificates
    robot_key=$certificates/robotkey.pem
    robot_crt=$certificates/robotcert.pem
    cmsweb_key=$certificates/cmsweb-hostkey.pem
    cmsweb_crt=$certificates/cmsweb-hostcert.pem

    # check (and copy if necessary) hostkey/hostcert.pem files in configuration area of frontend
    if [ ! -f $conf/frontend/hostkey.pem ]; then
        cp $cmsweb_key $conf/frontend/hostkey.pem
    fi
    if [ ! -f $conf/frontend/hostcert.pem ]; then
        cp $cmsweb_crt $conf/frontend/hostcert.pem
    fi

    tls_key=/tmp/$USER/tls.key
    tls_crt=/tmp/$USER/tls.crt
    proxy=/tmp/$USER/proxy

    # clean-up if these files exists
    for fname in $tls_key $tls_crt $proxy; do
        if [ -f $fname ]; then
            rm $fname
        fi
    done

    # for ingress controller we need tls.key/tls.crt names
    cp $cmsweb_key $tls_key
    cp $cmsweb_crt $tls_crt

    # create secrets with our robot certificates
    kubectl create secret generic robot-secrets \
        --from-file=$robot_key --from-file=$robot_crt \
        $files --dry-run -o yaml | \
        kubectl apply --validate=false -f -

    # create proxy secrets
    voms-proxy-init -voms cms -rfc \
        --key $robot_key --cert $robot_crt --out $proxy
    if [ -f $proxy ]; then
        kubectl create secret generic proxy-secrets \
            --from-file=$proxy --dry-run -o yaml | \
            kubectl apply --validate=false -f -
        rm $proxy
    fi

    echo "+++ generate cmsweb service secrets"
    # create secret files for deployment, they are based on
    # - robot key (pem file)
    # - robot certificate (pem file)
    # - cmsweb hostkey (pem file)
    # - cmsweb hostcert (pem file)
    # - hmac secret file
    # - configuration files from service configuration area
    for srv in $cmsweb_srvs; do
        local sdir=$conf/$srv
        # the underscrore is not allowed in secret names
        srv=`echo $srv | sed -e "s,_,,g"`
        local files=""
        if [ -d $sdir ] && [ -n "`ls $sdir`" ]; then
            for fname in $sdir/*; do
                files="$files --from-file=$fname"
            done
        fi
        # special case for DBS instances
        if [ "$srv" == "dbs" ]; then
            for inst in $dbs_instances; do
                local dbsfiles=""
                if [ -d "$sdir-$inst" ] && [ -n "`ls $sdir-$inst`" ]; then
                    for fconf in $sdir-$inst/*; do
                        dbsfiles="$dbsfiles --from-file=$fconf"
                    done
                fi
                kubectl create secret generic ${srv}-${inst}-secrets \
                    --from-file=$robot_key --from-file=$robot_crt \
                    --from-file=$hmac \
                    $files $dbsfiles --dry-run -o yaml | \
                    kubectl apply --validate=false -f -
            done
        else
            kubectl create secret generic ${srv}-secrets \
                --from-file=$robot_key --from-file=$robot_crt \
                --from-file=$hmac \
                $files --dry-run -o yaml | \
                kubectl apply --validate=false -f -
        fi
    done

    # create ingress secrets file, it requires tls.key/tls.crt files
    kubectl create secret generic ing-secrets \
        --from-file=$tls_key --from-file=$tls_crt --dry-run -o yaml | \
        kubectl apply --validate=false -f -
    rm $tls_key $tls_crt

    # use one of the option below
    # generate tls.key/tls.crt for custom CA and openssl config
#    echo "+++ create secrets for TLS case"
#    openssl genrsa -out tls.key 3072 -config openssl.cnf; openssl req -new -x509 -key tls.key -sha256 -out tls.crt -days 730 -config openssl.cnf -subj "/CN=cmsweb-test.web.cern.ch"

    # generate tls.key/tls.crt without openssl config
    #openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=cmsweb-test.web.cern.ch"

    # create secret with our tls.key/tls.crt
#    kubectl create secret tls cluster-tls-cert --key=tls.key --cert=tls.crt

    # create secret with our key/crt (they can be generated at ca.cern.ch/ca, see Host certificates)
    # we need to use this option if ing-nginx.yaml will contain the following configuration
    # tls:
    #    - secretName: cluster-tls-cert
    echo
    echo "+++ create cluster tls secret from key=$cmsweb_key, cert=$cmsweb_crt"
    kubectl create secret tls cluster-tls-cert --key=$cmsweb_key --cert=$cmsweb_crt

    echo
    echo "+++ list sercres and configmap"
    kubectl get secrets
    kubectl -n kube-system get secrets

}

deploy_monitoring()
{
    echo
    echo "+++ create monitoring namespace"
    if [ -z "`kubectl get namespaces | grep monitoring`" ]; then
        kubectl create namespace monitoring
    fi

    echo
    echo "+++ deploy monitoring services"
    kubectl -n monitoring apply -f monitoring/
    kubectl -n monitoring get deployments
    kubectl -n monitoring get pods
    prom=`kubectl -n monitoring get pods | grep prom | awk '{print $1}'`
    echo "### we may access prometheus locally as following"
    echo "kubectl -n monitoring port-forward $prom 8080:9090"
    echo "### to access prometheus externally we should do the following:"
    echo "ssh -S none -L 30000:$kubehost:30000 $USER@lxplus.cern.ch"
}

# deploy appripriate ingress controller for our cluster
deploy_ingress()
{
    echo
    echo "+++ list configmap"
    kubectl -n kube-system get configmap

    echo
    echo "+++ label node"
    for n in `kubectl get nodes | grep -v master | grep -v NAME | awk '{print $1}'`; do
        kubectl label node $n role=ingress --overwrite
        kubectl get node -l role=ingress
    done

    echo
    echo "+++ deploy $cmsweb_ing"
    kubectl apply -f ingress/${cmsweb_ing}.yaml
}

deploy_crons()
{
    echo
    echo "+++ deploy crons"
    kubectl apply -f crons/
}

deploy_services()
{
    echo
    echo "+++ deploy services: $cmsweb_srvs"
    for srv in $cmsweb_srvs; do
        if [ "$srv" == "dbs" ]; then
            for inst in $dbs_instances; do
                if [ -f "$sdir/${srv}-${inst}.yaml" ]; then
                    kubectl apply -f "$sdir/${srv}-${inst}.yaml" --validate=false
                fi
            done
        else
            if [ -f $sdir/${srv}.yaml ]; then
                kubectl apply -f $sdir/${srv}.yaml --validate=false
            fi
        fi
    done
}

# Main routine, perform action requested on command line.
case ${1:-status} in
  cleanup )
    cleanup
    check
    ;;

  create | services | frontend )
    deploy_secrets
    deploy_services
    deploy_ingress
    deploy_crons
    deploy_monitoring
    ;;

  secrets )
    deploy_secrets
    ;;

  status )
    check
    ;;

  scale )
    scale
    ;;

  help )
    perl -ne '/^##H/ && do { s/^##H ?//; print }' < $0
    ;;

  * )
    perl -ne '/^##H/ && do { s/^##H ?//; print }' < $0
    ;;
esac