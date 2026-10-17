#!/bin/bash
# train.sh <ds_dir> <mod_dir> <max_iterations>
set -e
cd "$(dirname "$0")"
DS=$1; MOD=$2; IT=$3
mkdir -p $MOD
lstmtraining --continue_from ex/u.lstm --old_traineddata tdb/ukr.traineddata \
  --traineddata td2/ukr/ukr.traineddata --model_output $MOD/ck \
  --train_listfile $DS/list.txt --max_iterations $IT --target_error_rate 0.005 \
  --debug_interval -1 > $MOD/log.txt 2>&1
mkdir -p $MOD/float $MOD/int
lstmtraining --stop_training --continue_from $MOD/ck_checkpoint --traineddata td2/ukr/ukr.traineddata \
  --model_output $MOD/float/ukr.traineddata >> $MOD/log.txt 2>&1
lstmtraining --stop_training --convert_to_int --continue_from $MOD/ck_checkpoint --traineddata td2/ukr/ukr.traineddata \
  --model_output $MOD/int/ukr.traineddata >> $MOD/log.txt 2>&1
cp -r tdb/configs $MOD/float/ ; cp -r tdb/configs $MOD/int/
echo done $MOD
