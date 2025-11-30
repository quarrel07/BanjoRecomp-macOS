#include "patches.h"
#include "core1/ml.h"
#include "core1/mlmtx.h"

extern f32 sViewportPosition[3];
extern f32 sViewportFrustumPlanes[4][4];

int frustum_checks_enabled = TRUE;
void set_frustum_checks_enabled(int enabled) {
    frustum_checks_enabled = enabled;
}

RECOMP_PATCH bool viewport_isBoundingBoxInFrustum(f32 arg0[3], f32 arg1[3]) {
    return TRUE;
}

// @recomp Patched to allow globally disabling frustum checks.
RECOMP_PATCH bool viewport_func_8024DB50(f32 pos[3], f32 distance) {
    // @recomp Return true if frustum checks are disabled (always pass the frustum check).
    if (!frustum_checks_enabled) {
        return TRUE;
    }
    f32 delta[3];
    s32 i;

    delta[0] = pos[0] - sViewportPosition[0];
    delta[1] = pos[1] - sViewportPosition[1];
    delta[2] = pos[2] - sViewportPosition[2];

    for(i = 0; i < 4; i++) {
        if(distance <= ml_vec3f_dot_product(delta, sViewportFrustumPlanes[i])) {
            return FALSE;
        }
    }

    return TRUE;
}
