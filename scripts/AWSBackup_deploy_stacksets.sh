#!/bin/bash

## Sample parameters for the script 
# bash ./scripts/AWSBackup_deploy_stacksets.sh --pBackupVaultName "btest" --pSourceBackupAccountID "xxxx" --pTargetBackupAccountID "xxxxx" --pSourceAWSRegion "us-east-2" --pDestinationAWSRegion "us-east-1" --pAWSOrganizationID "r-xxxx" --pBackupPlanName "backup-plan" --pScheduleExpression 'cron(0 0/4 * * ? *)' --pBackupTagKey "backup-plan" --pBackupTagValue "rds-backup-plan" --pDeleteAfterDays 1 

while [[ $# -gt 0 ]]
do
 case $1 in
    -n|--pBackupVaultName)
	pBackupVaultName="$2"
	shift 2
	;;
    -s|--pSourceBackupAccountID)
	pSourceBackupAccountID="$2"
	shift 2
	;;
    -t|--pTargetBackupAccountID)
	pTargetBackupAccountID="$2"
        shift 2
	;;
    -r|--pSourceAWSRegion)
        pSourceAWSRegion="$2"
        shift 2
	;;
    -d|--pDestinationAWSRegion)
	pDestinationAWSRegion="$2"
	shift 2
	;;
    -o|--pAWSOrganizationID)
	pAWSOrganizationID="$2"
	shift 2
	;;
    -p|--pBackupPlanName)
	pBackupPlanName="$2"
	shift 2
	;;
    -e|--pScheduleExpression)
	pScheduleExpression="$2"
	shift 2
	;;
    -k|--pBackupTagKey)
	pBackupTagKey="$2"
	shift 2
	;;
    -v|--pBackupTagValue)
	pBackupTagValue="$2"
	shift 2
	;;
    -D|--pDeleteAfterDays)
	pDeleteAfterDays="$2"
	pCopyDeleteAfterDays="$2"
	shift 2
	;;
    -h|--help)
      "This is a weather script"
      exit 2
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      exit 1
      ;;
  esac
done

echo "================================"
echo "Parameters passed for this run"
echo "================================"
echo "pBackupVaultName : $pBackupVaultName"
echo "pSourceBackupAccountID: $pSourceBackupAccountID"
echo "pTargetBackupAccountID: $pTargetBackupAccountID"
echo "pSourceAWSRegion: $pSourceAWSRegion"
echo "pDestinationAWSRegion: $pDestinationAWSRegion"
echo "pAWSOrganizationID: $pAWSOrganizationID"
echo "pBackupPlanName: $pBackupPlanName"
echo "pScheduleExpression: $pScheduleExpression"
echo "pBackupTagKey: $pBackupTagKey"
echo "pBackupTagValue: $pBackupTagValue"
echo "pDeleteAfterDays: $pDeleteAfterDays"
echo "pCopyDeleteAfterDays: $pCopyDeleteAfterDays"
echo ""

function check_stack_status()
{
 
   stacksetname=$1
   stackaccount=$2
   stackregion=$3
   status="NOTRUNNING"
   finalstatus="SUCCEEDED"
   sleep 60
   while [[ "${status}" != "${finalstatus}" ]]; do
      status=`aws cloudformation describe-stack-instance --stack-set-name ${stacksetname} --stack-instance-account ${stackaccount} --stack-instance-region ${stackregion} --query 'StackInstance.StackInstanceStatus.DetailedStatus' --output text`
      echo "Stack current status : ${status}, Sleeping for 60 sec before next check, Exit when ${finalstatus} status"
      sleep 60
   done
 
}

function deploy_source() 
{

   aws cloudformation create-stack-set \
	--stack-set-name "source-stack-1" --description "Stack instance for Source account and source region" \
	--template-body file://templates/AWSBackup_source.yaml  \
	--parameters ParameterKey=pBackupVaultName,ParameterValue="${pBackupVaultName}" \
                     ParameterKey=pTargetBackupAccountID,ParameterValue=${pTargetBackupAccountID} \
                     ParameterKey=pDestinationAWSRegion,ParameterValue="${pDestinationAWSRegion}" \
                     ParameterKey=pAWSOrganizationID,ParameterValue="${pAWSOrganizationID}" \
                     ParameterKey=pBackupPlanName,ParameterValue="${pBackupPlanName}" \
                     ParameterKey=pScheduleExpression,ParameterValue="${pScheduleExpression}" \
                     ParameterKey=pBackupTagKey,ParameterValue="${pBackupTagKey}" \
                     ParameterKey=pBackupTagValue,ParameterValue="${pBackupTagValue}" \
                     ParameterKey=pDeleteAfterDays,ParameterValue=${pDeleteAfterDays} \
                     ParameterKey=pCopyDeleteAfterDays,ParameterValue=${pCopyDeleteAfterDays} \
	--capabilities CAPABILITY_NAMED_IAM 

   aws cloudformation create-stack-instances --stack-set-name "source-stack-1" \
	--deployment-targets Accounts=${pSourceBackupAccountID} \
	--regions ${pSourceAWSRegion}

   check_stack_status "source-stack-1" "${pSourceBackupAccountID}" "${pSourceAWSRegion}"
}

function deploy_staging() 
{
   aws cloudformation create-stack-set \
        --stack-set-name "staging-stack-1" --description "Stack instance for Target account and in same region as source." \
        --template-body file://templates/AWSBackup_staging.yaml  \
        --parameters ParameterKey=pBackupVaultName,ParameterValue="${pBackupVaultName}" \
                     ParameterKey=pAWSOrganizationID,ParameterValue="${pAWSOrganizationID}" \
                     ParameterKey=pSourceBackupAccountID,ParameterValue="${pSourceBackupAccountID}" \
                     ParameterKey=pDestinationAWSRegion,ParameterValue="${pDestinationAWSRegion}" \
        --capabilities CAPABILITY_NAMED_IAM 

   aws cloudformation create-stack-instances --stack-set-name "staging-stack-1" \
        --deployment-targets Accounts=${pTargetBackupAccountID} \
        --regions ${pSourceAWSRegion}

   check_stack_status "staging-stack-1" "${pTargetBackupAccountID}" "${pSourceAWSRegion}"
}


function deploy_target() 
{
   aws cloudformation create-stack-set \
        --stack-set-name "target-stack-1" --description "Stack instance for Target Account and Target Region" \
        --template-body file://templates/AWSBackup_target.yaml  \
        --parameters ParameterKey=pBackupVaultName,ParameterValue="${pBackupVaultName}" \
                     ParameterKey=pSourceBackupAccountID,ParameterValue=${pSourceBackupAccountID} \
                     ParameterKey=pAWSOrganizationID,ParameterValue="${pAWSOrganizationID}" \
        --capabilities CAPABILITY_NAMED_IAM 

   aws cloudformation create-stack-instances --stack-set-name "target-stack-1" \
        --deployment-targets Accounts=${pTargetBackupAccountID} \
        --regions ${pDestinationAWSRegion}

   check_stack_status "target-stack-1" "${pTargetBackupAccountID}" "${pDestinationAWSRegion}"
}

function deploy_cfn_stacksets()
{
   echo "============================================================================"
   echo "Deploying StackSet to Source Account ${pSourceBackupAccountID}, Source Region ${pSourceAWSRegion}"
   echo "============================================================================"

   deploy_source

   if [[ "${pSourceBackupAccountID}" != "${pTargetBackupAccountID}" ]] && [[ "${pSourceAWSRegion}" != "${pDestinationAWSRegion}" ]]; then
       echo "============================================================================"
       echo "Cross Account Cross Region deployment"
       echo "Deploying StackSet to Staging: Target Account ${pTargetBackupAccountID}, Region ${pSourceAWSRegion}"
       echo "============================================================================"
       deploy_staging
   fi

   echo "============================================================================"
   echo "Deploying StackSet to Target Account ${pTargetBackupAccountID}, Target Region ${pDestinationAWSRegion}"
   echo "============================================================================"
   deploy_target
   echo "Stackset deployment completed successfully"
}

deploy_cfn_stacksets
