Shader "CMShader/Basic"
{
	Properties
	{
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
		_OutlineColor ("Outline Color", Color) = (0,0,0,1)
		[NoScaleOffset] _OutlineTex ("Outline Texture(RGB)", 2D) = "grey" {}
		[NoScaleOffset] _OutlineToonRamp ("Outline Toon Ramp (RGB)", 2D) = "white" {}
		_OutlineWidth ("Outline width", Range(0, 0.003)) = 0.0016
	}

	SubShader
	{
		Tags
		{
			"RenderType" = "Opaque"
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

		#pragma only_renderers d3d11 glcore gles
		#pragma target 4.0
		#include "cg/main.cginc"
		ENDCG

		Pass
		{
			Name "OUTLINE"
			Tags { "LIGHTMODE" = "FORWARDBASE" }

			Blend Off
			ZWrite On
			ZClip Off
			Cull Front

			CGPROGRAM
			#pragma vertex vertOutline
			#pragma fragment fragOutlineBase
			ENDCG
		}

		Pass
		{
			Name "OUTLINE"
			Tags { "LIGHTMODE" = "FORWARDADD" }

			Blend One One, One One
			ZWrite On
			ZClip Off
			Cull Front

			CGPROGRAM
			#pragma vertex vertOutline
			#pragma fragment fragOutlineAdd
			ENDCG
		}

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

