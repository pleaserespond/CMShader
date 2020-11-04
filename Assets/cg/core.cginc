#define DIFFUSE_RAW 1
#define UNITY_REQUIRE_FRAG_WORLDPOS 1
#define _EMISSION 1
#define UNITY_BRDF_GGX 1
#include "UnityCG.cginc"
#include "AutoLight.cginc"
#include "Lighting.cginc"
#include "UnityStandardCore.cginc"

CBUFFER_START(ToonyParams)

// Simple specular reflection power
float _Shininess;

// Texture for shadowed area
sampler2D _ShadowTex;

// Linear texture for light response
sampler2D _ToonRamp;

// Linear texture for shadow response
sampler2D _ShadowRateToon;

// Rim lighting
float3 _RimColor;
float _RimPower;
float _RimShift;

// Hilight
sampler2D _HiTex;
float _HiRate;
float _HiPow;

// Outline control
float4 _OutlineColor;
sampler2D _OutlineTex;
sampler2D _OutlineToonRamp;
float _OutlineWidth;

CBUFFER_END


/// Section vertex shaders {{{

struct VertexOutput
{
	float4 pos : SV_POSITION;
	float4 tex : TEXCOORD0;
	float4 tangentToWorldAndPackedData[3] : TEXCOORD1;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
	float4 posWorld : TEXCOORD4; // w holds if this is NOT outline
	half4 ambientOrLightmapUV : TEXCOORD5;    // SH or Lightmap UV
	UNITY_SHADOW_COORDS(6)
	UNITY_FOG_COORDS(7)
};

struct VertexOutputOutline
{
	float4 pos : SV_POSITION;
	float4 tex : TEXCOORD0;
	float3 normalWorld: TEXCOORD1;
	float4 posWorld : TEXCOORD2;
	UNITY_FOG_COORDS(3)
};

inline float3 vo_tangent(VertexOutput o)
{
	return o.tangentToWorldAndPackedData[0].xyz;
}

inline float3 vo_binormal(VertexOutput o)
{
	return o.tangentToWorldAndPackedData[1].xyz;
}

inline float3 vo_normal(VertexOutput o)
{
	return o.tangentToWorldAndPackedData[2].xyz;
}

inline void vo_normal(inout VertexOutput o, float3 normal)
{
	o.tangentToWorldAndPackedData[2].xyz = normal;
}

inline float3 vo_eyeVec(VertexOutput o)
{
	return float3(o.tangentToWorldAndPackedData[0].w, o.tangentToWorldAndPackedData[1].w, o.tangentToWorldAndPackedData[2].w);
}

inline half4 VertexGIForward(appdata_full v, float3 posWorld, half3 normalWorld)
{
    half4 ambientOrLightmapUV = 0;
    // Static lightmaps
    #ifdef LIGHTMAP_ON
        ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
        ambientOrLightmapUV.zw = 0;
    // Sample light probe for Dynamic objects only (no static or dynamic lightmaps)
    #elif UNITY_SHOULD_SAMPLE_SH
        #ifdef VERTEXLIGHT_ON
            // Approximated illumination from non-important point lights
            ambientOrLightmapUV.rgb = Shade4PointLights (
                unity_4LightPosX0,
				unity_4LightPosY0,
				unity_4LightPosZ0,
                unity_LightColor[0].rgb,
				unity_LightColor[1].rgb,
				unity_LightColor[2].rgb,
				unity_LightColor[3].rgb,
                unity_4LightAtten0,
				posWorld,
				normalWorld
			);
        #endif

        //ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, ambientOrLightmapUV.rgb);
        ambientOrLightmapUV.rgb += max(half3(0,0,0), ShadeSH9 (half4(normalWorld, 1.0)));
    #endif

    #ifdef DYNAMICLIGHTMAP_ON
        ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

    return ambientOrLightmapUV;
}

VertexOutput vert(appdata_full v)
{
	VertexOutput o;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.tex = v.texcoord;

	float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
	float3 normalWorld = UnityObjectToWorldNormal(v.normal);
	float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
	half3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
	o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
	o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
	o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
	float3 eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
	o.tangentToWorldAndPackedData[0].w = eyeVec.x;
	o.tangentToWorldAndPackedData[1].w = eyeVec.y;
	o.tangentToWorldAndPackedData[2].w = eyeVec.z;
	o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);
	o.posWorld = posWorld;
	UNITY_TRANSFER_SHADOW(o, v.uv1);
	UNITY_TRANSFER_FOG(o, o.pos);
	return o;
}

VertexOutputOutline vertOutline(appdata_full v)
{
	VertexOutputOutline o = (VertexOutputOutline)0;
	if (_OutlineWidth == 0) {
		o.pos.w = 1;
		return o;
	}
	o.pos = UnityObjectToClipPos(v.vertex);
	o.tex = v.texcoord;
	o.normalWorld = UnityObjectToWorldNormal(v.normal);
	const float fuck = 7;
	const float normalOffset=_OutlineWidth*fuck*clamp(o.pos.w, 0.01, 2);
	float3 nv=mul((float3x3)UNITY_MATRIX_VP, o.normalWorld);
	o.pos.xyz += normalOffset*nv;
	o.posWorld = mul(unity_ObjectToWorld, v.vertex);
	o.posWorld.xyz += normalOffset*o.normalWorld;
	UNITY_TRANSFER_FOG(o, o.pos);
	return o;
}

/// End section }}}


/// Section fragment setup {{{

struct DasFragmentData
{
    half4 diffColor, shadowColor;
	half3 hiColor;
    half3 normalWorld;
	float3 eyeVec, posWorld;
};

struct DasIndirect
{
	half3 diffuse;
	half3 specular;
};

struct DasGI
{
	UnityLight light;
	UnityIndirect indirect;
	half atten;
};

inline void ResetDasGI(out DasGI gi)
{
	ResetUnityLight(gi.light);
	gi.indirect.diffuse = 0;
	gi.indirect.specular = 0;
	gi.atten = 0;
}


inline DasFragmentData dasFragmentSetup(const float2 i_tex, const half3 i_eyeVec, const float4 tangentToWorld[3], const float3 i_posWorld)
{
	float2 uv = i_tex.xy * _MainTex_ST.xy + _MainTex_ST.zw;
	half4 diffuse = tex2D(_MainTex, uv) * _Color;

#if defined(_ALPHATEST_ON)
	clip (diffuse.a - _Cutoff);
#endif

#if defined(_ALPHADITHERTEST_ON)
	clipDither(diffuse.a, i_tex.xy);
#endif
	half4 shadow = tex2D(_ShadowTex, uv) * _Color;
	half4 hilight = tex2D(_HiTex, uv) * _Color;

#if defined(_ALPHAPREMULTIPLY_ON)
	// NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
	// Transparency 'removes' from Diffuse component
	diffuse.rgb *= diffuse.a;
#endif

	DasFragmentData o = (DasFragmentData)0;
	o.diffColor = diffuse;
	o.shadowColor = shadow;
	o.hiColor = hilight.rgb * hilight.a;
	o.normalWorld = PerPixelWorldNormal(float4(i_tex, 0, 1), tangentToWorld);
	o.eyeVec = NormalizePerPixelNormal(i_eyeVec);
	o.posWorld = i_posWorld;
	return o;
}

inline DasFragmentData dasFragmentSetupOutline(const float2 i_tex, const half3 i_eyeVec, const float4 tangentToWorld[3], const float3 i_posWorld)
{
	float2 uv = i_tex.xy * _MainTex_ST.xy + _MainTex_ST.zw;
	half4 color = half4(lerp(tex2D(_OutlineTex, uv).rgb, _OutlineColor.rgb, _OutlineColor.a), 1);

#if defined(_ALPHAPREMULTIPLY_ON)
	// NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
	// Transparency 'removes' from Diffuse component
	color.rgb *= color.a;
#endif

	DasFragmentData o = (DasFragmentData)0;
	o.diffColor = color;
	o.shadowColor = color;
	o.normalWorld = PerPixelWorldNormal(float4(i_tex, 0, 1), tangentToWorld);
	o.eyeVec = NormalizePerPixelNormal(i_eyeVec);
	o.posWorld = i_posWorld;
	return o;
}


inline DasGI dasGI_Base(UnityGIInput data, half3 normalWorld)
{
	DasGI o_gi;
	ResetDasGI(o_gi);
	o_gi.light = data.light;
	o_gi.atten = data.atten;

	// Base pass with Lightmap support is responsible for handling ShadowMask / blending here for performance reason
#if defined(HANDLE_SHADOWS_BLENDING_IN_GI)
	half bakedAtten = UnitySampleBakedOcclusion(data.lightmapUV.xy, data.worldPos);
	float zDist = dot(_WorldSpaceCameraPos - data.worldPos, UNITY_MATRIX_V[2].xyz);
	float fadeDist = UnityComputeShadowFadeDistance(data.worldPos, zDist);
	o_gi.atten = UnityMixRealtimeAndBakedShadows(data.atten, bakedAtten, UnityComputeShadowFade(fadeDist));
#endif

// 0 = flat
// 1 = linear
// 2 = square

#ifndef DAS_SH_MODE
#	define DAS_SH_MODE 2
#endif

#if DAS_SH_MODE == 0
	o_gi.indirect.diffuse = half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
#elif DAS_SH_MODE == 1
	o_gi.indirect.diffuse = SHEvalLinearL0L1(half4(normalWorld, 1));
#else
	o_gi.indirect.diffuse = ShadeSH9(half4(normalWorld, 1));
#endif

#if defined(LIGHTMAP_ON)
	// Baked lightmaps
	half4 bakedColorTex = UNITY_SAMPLE_TEX2D(unity_Lightmap, data.lightmapUV.xy);
	half3 bakedColor = DecodeLightmap(bakedColorTex);

#	ifdef DIRLIGHTMAP_COMBINED
	fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER (unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);
	o_gi.indirect.diffuse = DecodeDirectionalLightmap (bakedColor, bakedDirTex, normalWorld);

#		if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
	ResetUnityLight(o_gi.light);
	o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap (o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
#	endif

#	else // not directional lightmap
	o_gi.indirect.diffuse = bakedColor;

#		if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
	ResetUnityLight(o_gi.light);
	o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap(o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
#		endif

#	endif
#endif

#ifdef DYNAMICLIGHTMAP_ON
	// Dynamic lightmaps
	fixed4 realtimeColorTex = UNITY_SAMPLE_TEX2D(unity_DynamicLightmap, data.lightmapUV.zw);
	half3 realtimeColor = DecodeRealtimeLightmap (realtimeColorTex);

#	ifdef DIRLIGHTMAP_COMBINED
	half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
	o_gi.indirect.diffuse += DecodeDirectionalLightmap (realtimeColor, realtimeDirTex, normalWorld);
#	else
	o_gi.indirect.diffuse += realtimeColor;
#	endif
#endif
	return o_gi;
}

inline DasGI dasFragmentGI (DasFragmentData s, half4 i_ambientOrLightmapUV, UnityLight light)
{
	UnityGIInput d;
	d.light = light;
	d.worldPos = s.posWorld;
	d.worldViewDir = -s.eyeVec;
	d.atten = 1; // attenuation handled in toon brdf
#if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
	d.ambient = 0;
	d.lightmapUV = i_ambientOrLightmapUV;
#else
	d.ambient = i_ambientOrLightmapUV.rgb;
	d.lightmapUV = 0;
#endif

	d.probeHDR[0] = unity_SpecCube0_HDR;
	d.probeHDR[1] = unity_SpecCube1_HDR;
#if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
	d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
#endif
#ifdef UNITY_SPECCUBE_BOX_PROJECTION
	d.boxMax[0] = unity_SpecCube0_BoxMax;
	d.probePosition[0] = unity_SpecCube0_ProbePosition;
	d.boxMax[1] = unity_SpecCube1_BoxMax;
	d.boxMin[1] = unity_SpecCube1_BoxMin;
	d.probePosition[1] = unity_SpecCube1_ProbePosition;
#endif

	// Base pass with Lightmap support is responsible for handling ShadowMask / blending here for performance reason
#if defined(HANDLE_SHADOWS_BLENDING_IN_GI)
	half bakedAtten = UnitySampleBakedOcclusion(data.lightmapUV.xy, data.worldPos);
	float zDist = dot(_WorldSpaceCameraPos - data.worldPos, UNITY_MATRIX_V[2].xyz);
	float fadeDist = UnityComputeShadowFadeDistance(data.worldPos, zDist);
	d.atten = UnityMixRealtimeAndBakedShadows(data.atten, bakedAtten, UnityComputeShadowFade(fadeDist));
#endif

	DasGI gi;
	gi = dasGI_Base(d, s.normalWorld);
	gi.indirect.specular = 0;//dasGI_IndirectSpecular(d, 1, g);
	return gi;
}

/// End section fragment setup }}}

/// Section BRDF {{{

inline half4 BRDFEval(half atten, half occlusion, const DasFragmentData s, const UnityLight light, const UnityIndirect gi)
{
	half3 rim = 0;
	if (_RimPower>0.1) {
		rim = min(exp2(log2(1 - saturate(-dot(s.eyeVec, s.normalWorld)) + _RimShift) * _RimPower), 1.0) * _RimColor;
	}
	const float3 halfVec = Unity_SafeNormalize(light.dir - s.eyeVec);
	const float halfNorm = saturate(dot(halfVec, s.normalWorld));
	const half3 colorWithRim = s.diffColor.rgb + rim;
#ifdef USING_DIRECTIONAL_LIGHT
	const float ndotl = dot(s.normalWorld, light.dir);
	const float lightFacing = ndotl * 0.5 + 0.5;
	const half3 toonRampColor = tex2D(_ToonRamp, float2(lightFacing, 0.5)).rgb;
	const half shadowCoord = min(lightFacing, atten);
	const half shadowRateToonTex = tex2D(_ShadowRateToon, float2(shadowCoord, 0.5)).r;
	/// Final lit color
	half3 toonLit = colorWithRim;
	if (_HiPow>0) {
		const float hiIntensity = pow(halfNorm, _HiPow);
		const half3 hilight = hiIntensity * s.hiColor * _HiRate;
		toonLit += hilight;
	}
	const half3 toonDiffuse = lerp(toonLit, s.shadowColor.rgb, (1 - shadowRateToonTex) * s.shadowColor.a);
	const half3 diffuse = light.color * toonRampColor * toonDiffuse;
#else
	const half3 toonDiffuse = colorWithRim;
	const half3 diffuse = toonDiffuse * atten;
#endif

	half3 specular = 0;
	if (_Shininess > 0.0) {
		float shinyFactor = pow(halfNorm, 48);
		specular = (shinyFactor * _Shininess * atten).xxx;
	}

	return half4(
		diffuse + specular + colorWithRim * gi.diffuse * occlusion,
		s.diffColor.a
	);
}


inline half4 BRDFEvalOutline(half atten, half occlusion, const DasFragmentData s, const UnityLight light, const UnityIndirect gi)
{
	half3 rim = 0;
	if (_RimPower>0.1) {
		rim = min(exp2(log2(1 - saturate(-dot(s.eyeVec, s.normalWorld)) + _RimShift) * _RimPower), 1.0) * _RimColor;
	}
	const half3 colorWithRim = s.diffColor.rgb + rim;
#ifdef USING_DIRECTIONAL_LIGHT
	const float ndotl = dot(s.normalWorld, light.dir);
	const float lightFacing = ndotl * 0.5 + 0.5;
	const half3 toonRampColor = tex2D(_ToonRamp, float2(lightFacing, 0.5)).rgb;
	const half shadowCoord = min(lightFacing, atten);
	const half shadowRateToonTex = tex2D(_ShadowRateToon, float2(shadowCoord, 0.5)).r;
	const half3 colorWithRimLit = lerp(colorWithRim, s.shadowColor.rgb, (1 - shadowRateToonTex) * s.shadowColor.a);
	const half3 diffuse = light.color * toonRampColor * colorWithRimLit;//lerp(_ShadowColor, colorWithRimLit, atten);
#else
	const half3 colorWithRimLit = colorWithRim;
	const half3 diffuse = colorWithRimLit * atten;
#endif

	//*
	half3 specular = 0;
	if (_Shininess > 0.0) {
		half3 halfVec = light.dir - s.eyeVec;
		half halfVecNorm = dot(halfVec, halfVec);
		if (halfVecNorm>1e-3) halfVecNorm = 1/sqrt(halfVecNorm);
		else halfVecNorm = 0;
		float shinyFactor = pow(max(dot(s.normalWorld, halfVec), 0)*halfVecNorm, 48);
		specular = shinyFactor * _Shininess * atten;
	}
	// */

	return half4(
		diffuse + specular + colorWithRim * gi.diffuse * occlusion,
		s.diffColor.a
	);
}

/// End section BRDF }}}


#define DEBUG_UNITY_MATERIAL 0

half4 fragOutlineBase(VertexOutput i) : SV_TARGET
{
	return half4(0, 0, 0, 1);
#if DEBUG_UNITY_MATERIAL
	discard;
#endif
	DasFragmentData s = dasFragmentSetupOutline(i.tex, vo_eyeVec(i), i.tangentToWorldAndPackedData, i.posWorld.xyz);
	UNITY_SETUP_INSTANCE_ID(i);
	UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

	UnityLight mainLight = MainLight ();
	UNITY_LIGHT_ATTENUATION(atten, i, s.posWorld);

	half occlusion = Occlusion(i.tex.xy);
	DasGI gi = dasFragmentGI(s, i.ambientOrLightmapUV, mainLight);
	half4 c = BRDFEvalOutline(atten, occlusion, s, gi.light, gi.indirect);
	return half4(0, 0, 0, 1);
}

half4 fragOutlineAdd(VertexOutput i) : SV_TARGET
{
#if DEBUG_UNITY_MATERIAL
	discard;
#endif
	return half4(0, 0, 0, 0);
}

half4 fragBase(VertexOutput i) : SV_Target
{
	DasFragmentData s = dasFragmentSetup(i.tex, vo_eyeVec(i), i.tangentToWorldAndPackedData, i.posWorld.xyz);
	UNITY_SETUP_INSTANCE_ID(i);
	UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

	UnityLight mainLight = MainLight ();
	UNITY_LIGHT_ATTENUATION(atten, i, s.posWorld);

	half occlusion = Occlusion(i.tex.xy);
	DasGI gi = dasFragmentGI(s, i.ambientOrLightmapUV, mainLight);

#if !DEBUG_UNITY_MATERIAL
	half4 c = BRDFEval(atten, occlusion, s, gi.light, gi.indirect);
#else
	gi.light.color *= atten;
	UnityIndirect indirect;
	indirect.diffuse = gi.indirect.diffuse * occlusion;
	indirect.specular = gi.indirect.specular * occlusion;
	half4 c = BRDF1_Unity_PBS(s.diffColor, half3(1, 1, 1), 0.5, 0.5, s.normalWorld, -s.eyeVec, gi.light, indirect);
#endif
	c.rgb += Emission(i.tex.xy);

	UNITY_APPLY_FOG(i.fogCoord, c.rgb);
	return OutputForward (c, c.a);
}

half4 fragAdd(VertexOutput i) : SV_Target
{
	DasFragmentData s = dasFragmentSetup(i.tex, vo_eyeVec(i), i.tangentToWorldAndPackedData, i.posWorld.xyz);
	UNITY_LIGHT_ATTENUATION(atten, i, s.posWorld)
	UnityLight light = AdditiveLight (UnityWorldSpaceLightDir(s.posWorld), 1);

#if !DEBUG_UNITY_MATERIAL
	UnityIndirect noIndirect = ZeroIndirect();
	half4 c = BRDFEval(atten, 0, s, light, noIndirect);
#else
	light.color *= atten;
	UnityIndirect noIndirect = ZeroIndirect();
	half4 c = BRDF1_Unity_PBS(s.diffColor, half3(1, 1, 1), 0.5, 0.5, s.normalWorld, -s.eyeVec, light, noIndirect);
#endif

	UNITY_APPLY_FOG_COLOR(i.fogCoord, c.rgb, half4(0,0,0,0)); // fog towards black in additive pass
	return OutputForward (c, c.a);
}

/// End section standard fragment shaders }}}

