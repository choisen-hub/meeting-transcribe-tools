#!/usr/bin/env python3
import argparse, os, re, subprocess, tempfile
from pathlib import Path

def extract_gdrive_id(url):
    m = re.search(r'/d/([a-zA-Z0-9_-]+)', url)
    if m: return m.group(1)
    raise ValueError(f"ID 추출 실패: {url}")

def download_gdrive(url, work_dir):
    import gdown
    file_id = extract_gdrive_id(url)
    output = os.path.join(work_dir, file_id)
    print(f"  📥 다운로드 중... (ID: {file_id})")
    path = gdown.download(id=file_id, output=output, quiet=False)
    if not path or not os.path.exists(path): raise RuntimeError("다운로드 실패")
    return path, os.path.basename(path)

def extract_audio(video_path, work_dir):
    audio_path = os.path.join(work_dir, "audio.wav")
    print("  🎵 오디오 추출 중...")
    cmd = ["ffmpeg", "-i", video_path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", audio_path, "-y", "-loglevel", "error"]
    r = subprocess.run(cmd)
    return audio_path if r.returncode == 0 else video_path

def transcribe_audio(audio_path, model_name, language):
    import whisper
    print(f"  🤖 Whisper {model_name} 전사 중...")
    model = whisper.load_model(model_name)
    return model.transcribe(audio_path, language=language, verbose=False)

def save_transcript(result, output_base, title):
    os.makedirs(os.path.dirname(output_base), exist_ok=True)
    txt_path = output_base + ".txt"
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write(f"# {title}\n\n")
        for seg in result["segments"]:
            t = int(seg["start"])
            f.write(f"[{t//3600:02d}:{(t%3600)//60:02d}:{t%60:02d}] {seg['text'].strip()}\n")
    print(f"  ✅ 저장: {txt_path}")
    return txt_path

def process_one(url, model_name, language, output_dir):
    with tempfile.TemporaryDirectory() as work_dir:
        media_path, title = download_gdrive(url, work_dir)
        audio_path = extract_audio(media_path, work_dir)
        result = transcribe_audio(audio_path, model_name, language)
        safe_name = re.sub(r'[\\/*?:"<>|]', "", title)[:80]
        return save_transcript(result, os.path.join(output_dir, safe_name), title)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("urls", nargs="+")
    parser.add_argument("--model", default="small", choices=["tiny","base","small","medium","large"])
    parser.add_argument("--language", default="ko")
    parser.add_argument("--output", default=os.path.expanduser("~/Desktop/대화록"))
    args = parser.parse_args()
    os.makedirs(args.output, exist_ok=True)
    print(f"\n🎬 {len(args.urls)}개 처리 시작 | 모델: {args.model}\n")
    results = []
    for i, url in enumerate(args.urls, 1):
        print(f"[{i}/{len(args.urls)}] {url[:60]}...")
        try:
            path = process_one(url, args.model, args.language, args.output)
            if path: results.append(path)
        except Exception as e:
            print(f"  ❌ 오류: {e}")
    print(f"\n🎉 완료! {len(results)}/{len(args.urls)}개")
    for r in results: print(f"  → {r}")

if __name__ == "__main__":
    main()
