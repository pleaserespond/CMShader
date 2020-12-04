Shader "CMShader/Cutout"
{
	Properties
	{
		_Cutoff ("Cutoff", Range(0, 1)) = 0
		_Color ("Main Color", Color) = (0.5,0.5,0.5,1)
		_MainTex ("Base (RGB)", 2D) = "white" {}
		[NoScaleOffset] _ShadowTex ("Shadow Texture(RGBA)", 2D) = "white" {}
		[NoScaleOffset] _ToonRamp ("Toon Ramp (RGB)", 2D) = "gray" {}
		[NoScaleOffset] _ShadowRateToon ("Shadow Rate Toon (RGB)", 2D) = "white" {}
		[NoScaleOffset] _BumpMap ("Normal Map (RGB)", 2D) = "bump" {}
		_RimColor ("Rim Color", Color) = (0,0,1)
		_RimPower ("Rim Power", Range(0, 30)) = 3
		_RimShift ("Rim Shift", Range(0, 1)) = 0
		_Shininess ("Shininess", Range(0, 1)) = 0
		[NoScaleOffset] _HiTex ("Hilight (RGB)", 2D) = "white" {}
		_HiRate ("Hilight Rate", Range(0, 1)) = 0
		_HiPow ("Hilight Pow", Range(0, 50)) = 0
	}

	SubShader
	{
		Tags
		{
			"QUEUE" = "AlphaTest"
			"RenderType" = "TransparentCutout"
		}

		CGINCLUDE
		#if defined(UNITY_PASS_FORWARDBASE) || defined(UNITY_PASS_FORWARDADD)
			#pragma multi_compile_fog
		#endif
		#if defined(UNITY_PASS_FORWARDBASE)
			#pragma multi_compile_fwdbase
		#elif defined(UNITY_PASS_FORWARDADD)
			#pragma multi_compile_fwdadd_fullshadows
		#endif

		#define _ALPHATEST_ON 1
		#pragma only_renderers d3d11 glcore gles
		#pragma target 4.0
		#include "cg/main.cginc"
		ENDCG

		//*
		Pass
		{

			Name "FORWARD"
			Tags { "LIGHTMODE" = "FORWARDBASE" }

			Blend Off
			ZWrite On
			Cull Back

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment fragBase
			ENDCG
		}
		// */

		//*
		Pass
		{
			Name "FORWARD"
			Tags { "LIGHTMODE" = "FORWARDADD" }
			Blend One One
			BlendOp Add
			Cull Back

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment fragAdd
			ENDCG
		}
		// */
		
		//*
		Pass
		{
			Name "SHADOW_CASTER"
			Tags{ "LIGHTMODE" = "SHADOWCASTER" }

			ZWrite On ZTest LEqual

			CGPROGRAM
			#pragma vertex vertShadowCaster
			#pragma fragment fragShadowCaster
			ENDCG
		}
		// */
	}
	FallBack "Diffuse"
}

