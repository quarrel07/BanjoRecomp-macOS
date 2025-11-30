#include "patches.h"
#include "transform_ids.h"
#include "core1/core1.h"

typedef struct {
    s16 model_id;
    // u8 pad2[0x2];
    f32 scale;
    f32 rotation_speed;
}SkyInfo;

typedef struct {
    s16 map;
    // u8 pad2[2];
    SkyInfo sky_list[3];
}MapSkyInfo;

extern struct  
{
    MapSkyInfo *sky_info;
    BKModel *model[3];
    BKModelBin *model_bins[3];
    f32 timer;
} gcSky;

// @recomp Patched to tag the skybox projection and skybox models.
RECOMP_PATCH void sky_draw(Gfx **gfx, Mtx **mtx, Vtx **vtx){
    int i;
    f32 position[3];
    f32 rotation[3];
    BKModelBin *iAsset;

    viewport_setNearAndFar(5.0f, 15000.0f);
    if(gcSky.model_bins[0]){
        drawRectangle2D(gfx, 0, 0, (s32)(f32) gFramebufferWidth, (s32)(f32)gFramebufferHeight,0, 0, 0); //fill screen with black
        // @recomp Set the skybox projection matrix group.
        gEXMatrixGroupSimpleNormal((*gfx)++, PROJECTION_SKYBOX_TRANSFORM_ID, G_EX_PUSH, G_MTX_PROJECTION, G_EX_EDIT_NONE);

        viewport_setRenderViewportAndPerspectiveMatrix(gfx, mtx);
        viewport_getPosition_vec3f(position);
        for(i = 0; i < 3; i++){
            iAsset = gcSky.model_bins[i];
            if(iAsset){
                rotation[0] = 0.0f;
                rotation[1] = gcSky.sky_info->sky_list[i].rotation_speed * gcSky.timer;
                rotation[2] = 0.0f;

                // @recomp Set the model transform ID before drawing the skybox.
                cur_drawn_model_transform_id = SKYBOX_TRANSFORM_ID_START + SKYBOX_MODEL_TRANSFORM_ID_COUNT * i;

                modelRender_draw(gfx, mtx, position, rotation, gcSky.sky_info->sky_list[i].scale, NULL, iAsset);

                // @recomp Clear the model transform ID after drawing the skybox.
                cur_drawn_model_transform_id = 0;
            }
        }

        // @recomp Pop the skybox projection matrix group.
        gEXPopMatrixGroup((*gfx)++, G_MTX_PROJECTION);
    }
    else{//L8030B200
        drawRectangle2D(gfx, 0, 0, (s32)(f32) gFramebufferWidth, (s32)(f32)gFramebufferHeight, 0, 0, 0);
    }//L8030B254
}
