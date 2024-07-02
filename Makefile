# Ensure TF_VAR_SUBSCRIPTION_ID is set before running the target
ifndef TF_VAR_SUBSCRIPTION_ID
$(error TF_VAR_SUBSCRIPTION_ID is undefined. Please set TF_VAR_SUBSCRIPTION_ID to your Azure subscription ID.)
endif

SET_ENV = export
CLEAN = rm -rf terraform/.terraform terraform/.terraform.lock.hcl terraform/terraform.tfstate terraform/terraform.tfstate.backup terraform/env.sh
AZURE_LOGIN = az login
AZURE_SP_CREATE = az ad sp create-for-rbac --name "homework" --role "Owner" --scopes "/subscriptions/$$TF_VAR_SUBSCRIPTION_ID"

start:
	$(AZURE_LOGIN) && \
	SP_JSON=$$($(AZURE_SP_CREATE)) && \
	$(SET_ENV) TF_VAR_CLIENT_ID=$$(echo $${SP_JSON} | jq -r .appId) && \
	$(SET_ENV) TF_VAR_CLIENT_SECRET=$$(echo $${SP_JSON} | jq -r .password) && \
	$(SET_ENV) TF_VAR_TENANT_ID=$$(echo $${SP_JSON} | jq -r .tenant) && \
	sleep 65 && \
	az role assignment create --assignee $${TF_VAR_CLIENT_ID} --role "Storage Blob Data Contributor" --scope "/subscriptions/$${TF_VAR_SUBSCRIPTION_ID}" && \
	cd terraform && \
	terraform init && \
	terraform apply -auto-approve && \
	$(SET_ENV) RESOURCE_GROUP_NAME=$$(terraform output -json | jq -r .resource_group_name.value) && \
	$(SET_ENV) ACR_LOGIN_SERVER=$$(terraform output -json | jq -r .acr_login_server.value) && \
	$(SET_ENV) ACR_NAME=$$(terraform output -json | jq -r .acr_name.value) && \
	$(SET_ENV) KUBERNETES_CLUSTER_NAME=$$(terraform output -json | jq -r .kubernetes_cluster_name.value) && \
	$(SET_ENV) KUBERNETES_CLUSTER_HOST=$$(terraform output -json | jq -r .kubernetes_cluster_host.value) && \
	$(SET_ENV) STORAGE_ACCOUNT_NAME=$$(terraform output -json | jq -r .storage_account_name.value) && \
	$(SET_ENV) STORAGE_CONTAINER_NAME=$$(terraform output -json | jq -r .storage_container_name.value) && \
	$(SET_ENV) ACR_ID=$$(az acr show --name $${ACR_NAME} --resource-group $${RESOURCE_GROUP_NAME} --query "id" -o tsv) && \
	az role assignment create --assignee $${TF_VAR_CLIENT_ID} --role Owner --scope $${ACR_ID} && \
	echo "$(SET_ENV) TF_VAR_CLIENT_ID=$$TF_VAR_CLIENT_ID" >> env.sh && \
	echo "$(SET_ENV) TF_VAR_CLIENT_SECRET=$$TF_VAR_CLIENT_SECRET" >> env.sh && \
	echo "$(SET_ENV) TF_VAR_TENANT_ID=$$TF_VAR_TENANT_ID" >> env.sh && \
	echo "$(SET_ENV) RESOURCE_GROUP_NAME=$$RESOURCE_GROUP_NAME" >> env.sh && \
	echo "$(SET_ENV) ACR_LOGIN_SERVER=$$ACR_LOGIN_SERVER" >> env.sh && \
	echo "$(SET_ENV) ACR_NAME=$$ACR_NAME" >> env.sh && \
	echo "$(SET_ENV) KUBERNETES_CLUSTER_NAME=$$KUBERNETES_CLUSTER_NAME" >> env.sh && \
	echo "$(SET_ENV) KUBERNETES_CLUSTER_HOST=$$KUBERNETES_CLUSTER_HOST" >> env.sh && \
	echo "$(SET_ENV) STORAGE_ACCOUNT_NAME=$$STORAGE_ACCOUNT_NAME" >> env.sh  && \
	echo "$(SET_ENV) STORAGE_CONTAINER_NAME=$$STORAGE_CONTAINER_NAME" >> env.sh

build:
	cd terraform && \
	source env.sh && \
	cd ../connectors && \
	az login --service-principal --username $$TF_VAR_CLIENT_ID --password $$TF_VAR_CLIENT_SECRET --tenant $$TF_VAR_TENANT_ID && \
	az acr build --registry $$ACR_NAME --image azure-connector:latest -f Dockerfile . && \
	az aks update --name $$KUBERNETES_CLUSTER_NAME --resource-group $$RESOURCE_GROUP_NAME --attach-acr $$ACR_NAME

conf:
	cd terraform && \
	source env.sh && \
	cd .. && \
	az login --service-principal --username $$TF_VAR_CLIENT_ID --password $$TF_VAR_CLIENT_SECRET --tenant $$TF_VAR_TENANT_ID && \
	az aks get-credentials --resource-group $$RESOURCE_GROUP_NAME --name $$KUBERNETES_CLUSTER_NAME && \
	kubectl create namespace confluent || true && \
	kubectl config set-context --current --namespace confluent && \
	helm repo add confluentinc https://packages.confluent.io/helm && \
	helm repo update && \
	helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes && \
	kubectl apply -f confluent-platform.yaml && \
    kubectl apply -f producer-app-data.yaml && \
	kubectl create -f kstream-app.yaml

run:
	kubectl get pods -o wide  && \
    kubectl port-forward controlcenter-0 9021:9021

destroy:
	cd terraform && \
	source env.sh && \
	terraform destroy -auto-approve && \
	cd .. && \
	$(CLEAN)

clean:
	$(CLEAN)