#include "patches.h"
#include "prop.h"
#include "actor.h"
#include "functions.h"
#include "object_extension_funcs.h"
#include "bk_api.h"
#include "core2/coords.h"

// Max props per cube, limited by cube->prop2Cnt which is only 6 bits.
#define CUBE_MAX_PROPS 63
// Hardcoded cube limit, TODO implement a better solution that doesn't involve dedicating this much memory and allows for larger cube counts.
#define MAX_CUBES 4000
u32 prop_handles[MAX_CUBES][CUBE_MAX_PROPS];

void vtxList_getBounds_s32(BKVertexList *, s32[3], s32[3]);
enum map_e map_get(void);

extern struct {
    Cube *cubes;
    f32 margin;
    s32 min[3];
    s32 max[3];
    s32 stride[2];
    s32 cubeCnt; 
    s32 unk2C;
    s32 width[3];
    Cube *unk3C; // fallback cube?
    Cube *unk40; // some other fallback cube?
    s32 unk44; // index of some sort
} sCubeList;

typedef struct {
    s16 map_id; //enum map_e
    s16 opa_model_id; //enum asset_e level_model_id
    s16 xlu_model_id; //enum asset_e level2_model_id
    s16 unk6[3]; // min bounds (for cubes?)
    s16 unkC[3]; // max bounds (for cubes?)
    // u8 pad12[0x2];
    f32 scale;
}MapModelDescription;

extern struct {
    void *unk0;
    void *unk4;
    BKCollisionList *collision_opa;
    BKCollisionList *collision_xlu;
    BKModel *model_opa;
    BKModel *model_xlu;
    BKModelBin *model_bin_opa;
    BKModelBin *model_bin_xlu;
    s32 unk20;
    struct5Bs *unk24;
    MapModelDescription *description;
    u8 env_red;
    u8 env_green;
    u8 env_blue;
    f32 scale;
}mapModel;

void recomp_abort(const char* msg);

// @recomp Patched to verify the cube count is less than the fixed amount.
RECOMP_PATCH void mapModel_getCubeBounds(s32 min[3], s32 max[3]) {
    vtxList_getBounds_s32(model_getVtxList(mapModel.model_bin_opa), min, max);
    coords_scale(min, max, 1000);
    min[0] = min[0] + mapModel.description->unk6[0];
    min[1] = min[1] + mapModel.description->unk6[1];
    min[2] = min[2] + mapModel.description->unk6[2];
    max[0] = max[0] + mapModel.description->unkC[0];
    max[1] = max[1] + mapModel.description->unkC[1];
    max[2] = max[2] + mapModel.description->unkC[2];

    // @recomp Calculate and validate the cube count.
    u32 width0 = max[0] - min[0] + 1;
    u32 width1 = max[1] - min[1] + 1;
    u32 width2 = max[2] - min[2] + 1;
    u32 stride0 = width0;
    u32 stride1 = stride0 * width1;
    u32 cubeCnt = stride1 * width2;

    recomp_printf("Cube count for map %d: %u\n", map_get(), cubeCnt);
    if (cubeCnt > MAX_CUBES) {
        recomp_abort("Cube count too high\n");
    }
}
