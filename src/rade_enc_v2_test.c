/*
  rade_enc_v2_test.c  -- RADE V2 core encoder test tool.
  Reads feature vectors (float32) from stdin, runs CoreEncoderStatefull,
  writes latent vectors (float32) to stdout.

  Input:  float32, FRAMES_PER_STEP * NUM_FEATURES (4*21=84) per frame
  Output: float32, LATENT_DIM (56) per frame
*/

#include <stdio.h>
#include <stdlib.h>

#include "rade_fargan_config.h" /* to silence Opus build warnings */
#include "rade_enc_v2.h"
#include "rade_v2_constants.h"
#include "rade_v2_core.h"

int main(void)
{
    RADEEncV2      model;
    RADEEncV2State state;

    if (init_radeencv2(&model, radeencv2_arrays) != 0) {
        fprintf(stderr, "rade_enc_v2_test: failed to initialise encoder\n");
        return 1;
    }
    rade_init_encoder_v2(&state);

    const int n_in  = RADE_V2_FRAMES_PER_STEP * RADE_V2_NUM_FEATURES;
    const int n_out = RADE_V2_LATENT_DIM;

    float features[RADE_V2_FRAMES_PER_STEP * RADE_V2_NUM_FEATURES];
    float latents[RADE_V2_LATENT_DIM];
    int frames = 0;

    while (fread(features, sizeof(float), n_in, stdin) == (size_t)n_in) {
        rade_core_encoder_v2(&state, &model, latents, features, 0);
        fwrite(latents, sizeof(float), n_out, stdout);
        frames++;
    }

    fprintf(stderr, "rade_enc_v2_test: processed %d frames\n", frames);
    return 0;
}
