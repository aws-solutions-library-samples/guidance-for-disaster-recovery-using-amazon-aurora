#!/bin/bash

# Sample block to remove the recovery point
# for rarn in `aws backup  list-recovery-points-by-backup-vault --backup-vault-name "${pBackupVaultName}" --query 'RecoveryPoints[].RecoveryPointArn' --output text`
# do
# 	aws backup delete-recovery-point --backup-vault-name "${pBackupVaultName}" --recovery-point-arn ${rarn} --region "${pDestinationAWSRegion}"
# done


# Sample parameter for the run
## Parameters
# bash ./scripts/AWSBackup_cleanup_stacksets.sh --pBackupVaultName "btest" --pSourceBackupAccountID "3xxxxxxxxx" --pTargetBackupAccountID "1xxxxxxxxx" --pSourceAWSRegion "us-east-2" --pDestinationAWSRegion "us-east-1"

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
echo "pBackupVaultName: $pBackupVaultName"
echo "pSourceBackupAccountID: $pSourceBackupAccountID"
echo "pTargetBackupAccountID $pTargetBackupAccountID"
echo "pSourceAWSRegion: $pSourceAWSRegion"
echo "pDestinationAWSRegion: $pDestinationAWSRegion"
echo ""

function check_stack_instance_status()
{
   stacksetname=$1
   stackaccount=$2
   stackregion=$3
   status="NOTRUNNING"
   finalstatus="DELETED"
   while [[ "${status}" != "${finalstatus}" ]]; do
      sleep 60
      status=""
      status=`aws cloudformation describe-stack-instance --stack-set-name ${stacksetname} --stack-instance-account ${stackaccount} --stack-instance-region ${stackregion} --query 'StackInstance.StackInstanceStatus.DetailedStatus' --output text 2>/dev/null`
      if [[ -z "${status}" ]]; then
         status="DELETED"
      fi
      echo "Stack current status : ${status}, Sleeping for 60 sec before next check, Exit when ${finalstatus} status"
   done

}

function delete_source() 
{
   aws cloudformation delete-stack-instances --stack-set-name "source-stack-1" \
        --deployment-targets Accounts=${pSourceBackupAccountID} \
        --regions ${pSourceAWSRegion} --no-retain-stacks

   check_stack_instance_status "source-stack-1" "${pSourceBackupAccountID}" "${pSourceAWSRegion}"

   aws cloudformation delete-stack-set \
	--stack-set-name "source-stack-1"
}

function delete_staging() 
{
   aws cloudformation delete-stack-instances --stack-set-name "staging-stack-1" \
        --deployment-targets Accounts=${pTargetBackupAccountID} \
        --regions ${pSourceAWSRegion} --no-retain-stacks

   check_stack_instance_status "staging-stack-1" "${pTargetBackupAccountID}" "${pSourceAWSRegion}"

   aws cloudformation delete-stack-set \
        --stack-set-name "staging-stack-1"
}


function delete_target() 
{
   aws cloudformation delete-stack-instances --stack-set-name "target-stack-1" \
        --deployment-targets Accounts=${pTargetBackupAccountID} \
        --regions ${pDestinationAWSRegion} --no-retain-stacks

   check_stack_instance_status "target-stack-1" "${pTargetBackupAccountID}" "${pDestinationAWSRegion}"

   aws cloudformation delete-stack-set \
        --stack-set-name "target-stack-1" 
}

function delete_cfn_stacksets()
{

   echo "============================================================================"
   echo "Deleting StackSet in Target Account ${pTargetBackupAccountID}, Target Region ${pDestinationAWSRegion}"
   echo "============================================================================"
   delete_target

   if [[ "${pSourceBackupAccountID}" != "${pTargetBackupAccountID}" ]] && [[ "${pSourceAWSRegion}" != "${pDestinationAWSRegion}" ]]; then
      echo "============================================================================"
      echo "Cross Account Cross Region cleanup"
      echo "Deleting StackSet in Staging: Target Account ${pTargetBackupAccountID}, Region ${pSourceAWSRegion}"
      echo "============================================================================"
      delete_staging
   fi

   echo "============================================================================"
   echo "Deleting StackSet in Source Account ${pSourceBackupAccountID}, Source Region ${pSourceAWSRegion}"
   echo "============================================================================"
   delete_source

   echo "Stackset deletion completed successfully"
}

delete_cfn_stacksets
