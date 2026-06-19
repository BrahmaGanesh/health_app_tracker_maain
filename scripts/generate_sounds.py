import wave, struct, math, os

os.makedirs("static/sounds", exist_ok=True)

def make_tone(filename, freq_pattern, sample_rate=22050, volume=0.35):
    """freq_pattern: list of (frequency_hz, duration_sec, gap_after_sec)"""
    frames = []
    for freq, dur, gap in freq_pattern:
        n = int(sample_rate * dur)
        for i in range(n):
            # Envelope to avoid clicks (fade in/out)
            fade = min(1.0, i/(sample_rate*0.01), (n-i)/(sample_rate*0.01))
            val = volume * fade * math.sin(2*math.pi*freq*i/sample_rate)
            frames.append(int(val * 32767))
        gap_n = int(sample_rate * gap)
        frames.extend([0]*gap_n)

    with wave.open(filename, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(b''.join(struct.pack('<h', f) for f in frames))

# health_alert: two-tone alert beep (like a heart monitor ping)
make_tone("static/sounds/health_alert.mp3", [(880, 0.15, 0.08), (880, 0.15, 0.3)])

# water_drop: gentle descending drop sound
make_tone("static/sounds/water_drop.mp3", [(1200, 0.08, 0.0), (900, 0.08, 0.0), (700, 0.12, 0.0)])

# medicine: pleasant bell chime (two notes)
make_tone("static/sounds/medicine.mp3", [(1046, 0.2, 0.05), (1318, 0.25, 0.0)])

# gentle: soft single chime
make_tone("static/sounds/gentle.mp3", [(880, 0.35, 0.0)])

# urgent: rapid triple beep
make_tone("static/sounds/urgent.mp3", [(1000, 0.1, 0.05), (1000, 0.1, 0.05), (1000, 0.1, 0.05), (1000, 0.15, 0.0)])

print("Sound files generated:")
for f in os.listdir("static/sounds"):
    print(" -", f, os.path.getsize(f"static/sounds/{f}"), "bytes")