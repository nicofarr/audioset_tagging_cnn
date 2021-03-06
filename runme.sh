#!/bin/bash
DATASET_DIR="/vol/vssp/datasets/audio/audioset/audioset201906"
WORKSPACE="/vol/vssp/cvpnobackup/scratch_4weeks/qk00006/workspaces/pub_audioset_tagging_cnn_transfer"

# ============ Download dataset ============
echo "------ Download metadata ------"
mkdir -p $DATASET_DIR"/metadata"

# Video list csv
wget -O $DATASET_DIR"/metadata/eval_segments.csv" http://storage.googleapis.com/us_audioset/youtube_corpus/v1/csv/eval_segments.csv
wget -O $DATASET_DIR"/metadata/balanced_train_segments.csv" http://storage.googleapis.com/us_audioset/youtube_corpus/v1/csv/balanced_train_segments.csv
wget -O $DATASET_DIR"/metadata/unbalanced_train_segments.csv" http://storage.googleapis.com/us_audioset/youtube_corpus/v1/csv/unbalanced_train_segments.csv

# Class labels indices
wget -O $DATASET_DIR"/metadata/class_labels_indices.csv" http://storage.googleapis.com/us_audioset/youtube_corpus/v1/csv/class_labels_indices.csv

# Quality of counts
wget -O $DATASET_DIR"/metadata/qa_true_counts.csv" http://storage.googleapis.com/us_audioset/youtube_corpus/v1/qa/qa_true_counts.csv

echo "Download metadata to $DATASET_DIR/metadata"

# Split large unbalanced csv file (2,041,789) to 41 partial csv files. 
# Each csv file contains at most 50,000 audio info.
echo "------ Split unbalanced csv to csvs ------"
python3 utils/dataset.py split_unbalanced_csv_to_partial_csvs --unbalanced_csv=$DATASET_DIR/metadata/unbalanced_train_segments.csv --unbalanced_partial_csvs_dir=$DATASET_DIR"/metadata/unbalanced_partial_csvs"

echo "------ Download wavs ------"
# Download evaluation wavs
python3 utils/dataset.py download_wavs --csv_path=$DATASET_DIR"/metadata/eval_segments.csv" --audios_dir=$DATASET_DIR"/audios/eval_segments"

# Download balanced train wavs
python3 utils/dataset.py download_wavs --csv_path=$DATASET_DIR"/metadata/balanced_train_segments.csv" --audios_dir=$DATASET_DIR"/audios/balanced_train_segments"

# Download unbalanced train wavs. Users may consider executing the following
# commands in parallel. One simple way is to open 41 terminals and execute
# one command in one terminal.
for IDX in {00..40}; do
  echo $IDX
  python utils/dataset.py download_wavs --csv_path=$DATASET_DIR"/metadata/unbalanced_csvs/unbalanced_train_segments_part$IDX.csv" --audios_dir=$DATASET_DIR"/audios/unbalanced_train_segments/unbalanced_train_segments_part$IDX"
done

# ============ Pack waveform and metadata to hdf5 ============
# Pack evaluation waveforms to a single hdf5 file
python3 utils/dataset.py pack_waveforms_to_hdf5 --csv_path=$DATASET_DIR"/metadata/eval_segments.csv" --audios_dir=$DATASET_DIR"/audios/eval_segments" --waveform_hdf5_path=$WORKSPACE"/hdf5s/waveforms/eval.h5" --target_hdf5_path=$WORKSPACE"/hdf5s/targets/eval.h5"

# Pack balanced training waveforms to a single hdf5 file
python3 utils/dataset.py pack_waveforms_to_hdf5 --csv_path=$DATASET_DIR"/metadata/balanced_train_segments.csv" --audios_dir=$DATASET_DIR"/audios/balanced_train_segments" --waveform_hdf5_path=$WORKSPACE"/hdf5s/waveforms/balanced_train.h5" --target_hdf5_path=$WORKSPACE"/hdf5s/targets/balanced_train.h5"

# Pack unbalanced training waveforms to hdf5 files. Users may consider 
# executing the following commands in parallel to speed up. One simple 
# way is to open 41 terminals and execute one command in one terminal.
for IDX in {00..40}; do
    echo $IDX
    python3 utils/dataset.py pack_waveforms_to_hdf5 --csv_path=$DATASET_DIR"/metadata/unbalanced_partial_csvs/unbalanced_train_segments_part$IDX.csv" --audios_dir=$DATASET_DIR"/audios/unbalanced_train_segments/unbalanced_train_segments_part$IDX" --waveform_hdf5_path=$WORKSPACE"/hdf5s/waveforms/unbalanced_train/unbalanced_train_part$IDX.h5" --target_hdf5_path=$WORKSPACE"/hdf5s/targets/unbalanced_train/unbalanced_train_part$IDX.h5"
done

python3 utils/dataset.py combine_full_target --target_hdf5s_dir=$WORKSPACE"/hdf5s/targets" --full_hdf5_path=$WORKSPACE"/hdf5s/targets/full_train.h5"

# Create black list (Optional). Audios in this balck list will not be used in training
python3 utils/create_black_list.py dcase2017task4 --workspace=$WORKSPACE

# ============ Train & Inference ============

python3 pytorch/main.py train --workspace=$WORKSPACE --data_type='full_train' --window_size=1024 --hop_size=320 --mel_bins=64 --fmin=50 --fmax=14000 --model_type='Cnn14' --loss_type='clip_bce' --balanced='balanced' --augmentation='mixup' --batch_size=32 --learning_rate=1e-3 --resume_iteration=0 --early_stop=1000000 --cuda

# Plot statistics
python3 utils/plot_statistics.py plot --dataset_dir=$DATASET_DIR --workspace=$WORKSPACE --select=1
