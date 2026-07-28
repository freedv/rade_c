/*---------------------------------------------------------------------------*\

  rade_dec_v2_test.c

  RADE V2 core decoder test tool.
  Reads latent vectors (float32) from stdin, runs the CoreDecoderStatefull,
  writes vocoder feature vectors (float32) to stdout.

  Usage:
      rade_dec_v2_test < latents.f32 > features.f32

  Input:  float32 stream, RADE_V2_LATENT_DIM (56) values per frame
  Output: float32 stream, RADE_V2_FRAMES_PER_STEP * RADE_V2_NUM_FEATURES
          (4 * 21 = 84) values per frame

\*---------------------------------------------------------------------------*/

/*
  Copyright (C) 2025 David Rowe

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions
  are met:

  - Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.

  - Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
  ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
  A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include <stdio.h>
#include <stdlib.h>

#include "rade_fargan_config.h" /* to silence Opus build warnings */
#include "rade_dec_v2.h"
#include "rade_v2_constants.h"
#include "rade_v2_core.h"

int main(void)
{
    RADEDecV2      model;
    RADEDecV2State state;

    if (init_radedecv2(&model, radedecv2_arrays) != 0) {
        fprintf(stderr, "rade_dec_v2_test: failed to initialise decoder\n");
        return 1;
    }
    rade_init_decoder_v2(&state);

    const int n_in  = RADE_V2_LATENT_DIM;
    const int n_out = RADE_V2_FRAMES_PER_STEP * RADE_V2_NUM_FEATURES;

    float latents[RADE_V2_LATENT_DIM];
    float features[RADE_V2_FRAMES_PER_STEP * RADE_V2_NUM_FEATURES];
    int frames = 0;

    while (fread(latents, sizeof(float), n_in, stdin) == (size_t)n_in) {
        rade_core_decoder_v2(&state, &model, features, latents, 0);
        fwrite(features, sizeof(float), n_out, stdout);
        frames++;
    }

    fprintf(stderr, "rade_dec_v2_test: processed %d frames\n", frames);
    return 0;
}
