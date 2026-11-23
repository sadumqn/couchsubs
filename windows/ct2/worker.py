# SPDX-License-Identifier: AGPL-3.0-only
"""Persistent, local CTranslate2 worker; protocol is one JSON object per line."""

import json
import os
import sys

cuda_dir = os.environ.get("COUCHSUBS_CUDA_DIR")
if cuda_dir:
    # CTranslate2 cuBLAS'ı dinamik yükler; dizin hem Python hem Win32 aramasına eklenir.
    _cuda_dll_handle = os.add_dll_directory(cuda_dir)
    import ctypes
    ctypes.windll.kernel32.SetDllDirectoryW(cuda_dir)

import sys


def reply(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


try:
    import ctranslate2

    device = sys.argv[2]
    translator = ctranslate2.Translator(
        sys.argv[1], device=device,
        compute_type="float16" if device == "cuda" else "int8",
        inter_threads=1,
        intra_threads=int(sys.argv[3]),
    )
    # Model yüklemesi başarılı olsa da CUDA bağımlılığı ilk çıkarımda hata verebilir.
    translator.translate_batch([["▁Hello", ".", "</s>"]], beam_size=1)
    reply({"ready": True})
except Exception as error:
    reply({"ready": False, "error": str(error)})
    sys.exit(1)

for line in sys.stdin:
    try:
        request = json.loads(line)
        result = translator.translate_batch(
            [request["tokens"]],
            beam_size=request["beams"],
            max_decoding_length=request["max_output"],
        )
        reply({"tokens": result[0].hypotheses[0]})
    except Exception as error:
        reply({"error": str(error)})
