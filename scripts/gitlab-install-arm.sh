#/bin/sh
az login
az account set --subscription "gopal-pay-as-you-go"
az account list \
   --refresh \
   --query "[?contains(name, 'gopal-pay-as-you-go')].id" \
   --output table

az account set --subscription c7f720a6-60fc-41f6-b3b6-b9063d8ab0db
