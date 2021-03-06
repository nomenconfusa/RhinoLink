(* ::Package:: *)

BeginPackage["RhinoLink`", {"NETLink`"}];


GHDeploy::usage = "GHDeploy[name, f, inputSpec, outputSpec] deploys a Grasshopper component that encapsulates Wolfram Language code.";


GHResult::usage = "GHResult[out1, out2, ...] returns multiple outputs from a Grasshopper component";


InstallRhinoPlugin::usage = "InstallRhinoPlugin[] installs the Rhino plugin and Grasshopper components that are part of RhinoLink. \
The Rhino plugin (WolframScripting.rhp and associated files) is installed via an installer executable provided with Rhino. \
The Grasshopper components are placed into the standard Grasshopper location for user components."


$RhinoHome::usage = "$RhinoHome is the path to the installation directory of Rhino. The default is \"c:\\Program Files\\Rhino 6\". You will need to set it to another value if you have a different location.";


$GrasshopperPath::usage = "$GrasshopperPath is the path to the directory containing Grasshopper DLLs (GH_IO.dll, Grasshopper.dll). It will have a default value suitable for Rhino 6, but can be changed if necessary.";


(* 
 * Data Type Conversions
 *)


FromRhino::usage = "FromRhino[obj] attempts to convert a Rhino object to an equivalent Wolfram Language expression. 
FromRhino[obj, type] attempts to convert a Rhino object of the specified type to an equivalent Wolfram Language expression.";


ToRhino::usage = "ToRhino[expr] attempts to convert a Wolfram Language expression to an equivalent Rhino object.";


(* 
 * Queries
 *)


RhinoDocObjects::usage = "RhinoDocObjects[doc] returns a list of the RhinoObjects in the document.";


(* 
 * Rhino Geometric Operations 
 *)


RhinoMeshUnion::usage = "RhinoMeshUnion[mesh1, mesh2] gives the mesh that is the union of mesh1 and mesh2.";


RhinoMeshIntersection::usage = "RhinoMeshIntersection[mesh1, mesh2] gives the mesh that is the intersection of mesh1 and mesh2.";


RhinoMeshDifference::usage = "RhinoMeshDifference[mesh1, mesh2] gives the mesh that is the difference of mesh1 and mesh2.";


(* 
 * Other Rhino Operations 
 *)


RhinoShow::usage = "RhinoShow[rhinoObject] adds 'rhinoObject' to the active document and releases it.";


RhinoUnshow::usage = "RhinoUnshow[guid] removed the object referenced by 'guid' from the active document and releases it.";


RhinoReshow::usage = "RhinoReshow[guid, rhinoObject] replaces the object referenced by 'guid' in the the active document with 'rhinoObject'.";


Begin["`Private`"];


If[!StringQ[$RhinoHome],
    $RhinoHome = "C:\\Program Files\\Rhino 6"
];

(* The path to the directory containing Grasshopper DLLs (GH_IO.dll, Grasshopper.dll) *)
If[!StringQ[$GrasshopperHome],
    $GrasshopperHome = FileNameJoin[{$RhinoHome, "Plug-ins", "Grasshopper"}]
];

(* This is the directory into which GHDeploy-ed components will be placed. Grasshopper automatically loads .gha files from here. *)
$deployDir = FileNameJoin[{ParentDirectory[$UserBaseDirectory], "Grasshopper", "Libraries"}];


$thisPacletDir = ParentDirectory[DirectoryName[$InputFileName]];


(**********************************  InstallRhinoPlugin  *********************************)

(* Users run this once, on first use of RhinoLink, to get the binary components properly installed into their Rhino/Grasshopper layout.
   Developers can run this after every rebuild of the RhinoLink binary components.
   Installing the Rhino component, WolframScripting.rhp and associated DLLS, is done via creating a WolframScripting.rhi file and
   running the plugin installer provided by Rhino on this file. This will install into the latest versino of Rhino that is available
   on the machine. The Grasshopper parts are installed via a file into the standard location for Rhino 6. 
*)

InstallRhinoPlugin[] := 
    Module[{rhinoLibsDir, strm, tempFileName, zipFile, rhiFile},
        (* Create the RhinoAttach evaluator definition *)
        If[Head[$FrontEnd] === FrontEndObject,
            If[!MemberQ[CurrentValue[$FrontEnd, EvaluatorNames], "RhinoAttach" -> _],
                AppendTo[CurrentValue[$FrontEnd, EvaluatorNames],
                     "RhinoAttach" -> {"AutoStartOnLaunch" -> False, "MLOpenArguments" -> "-LinkMode Connect -LinkName RhinoAttach"}]
            ]
        ];
        (* Create a WolframScripting.rhi file in a temporary location and run it, which will launch the plugin
           installer provided with Rhino. An rhi file is just a zip file that contains the .rhp file and other support files.
        *)
        rhinoLibsDir = FileNameJoin[{$thisPacletDir, "Libraries", "Rhino"}];
        (* Here we capture the path to the kernel in a file to be included in the WolframScripting.rhi archive, 
           so that Rhino can find the kernel with no help from the user.
        *)
        strm = OpenWrite[FileNameJoin[{rhinoLibsDir, "kernelPath.txt"}]];
        WriteString[strm, FileNameJoin[{$InstallationDirectory, "WolframKernel.exe"}]];
        Close[strm];
        tempFileName = CreateFile[];
        DeleteFile[tempFileName];
        zipFile = CreateArchive[rhinoLibsDir, tempFileName];
        rhiFile = RenameFile[zipFile, zipFile <> ".rhi"];
        SystemOpen[rhiFile];
        (* Installing the Grasshopper components is a straight file copy. *)
        CopyFile[
            FileNameJoin[{$thisPacletDir, "Libraries", "Grasshopper", "WolframGrasshopperComponents.gha"}],
            FileNameJoin[{$deployDir, "WolframGrasshopperComponents.gha"}],
            OverwriteTarget -> True
        ];
        CopyFile[
            FileNameJoin[{$thisPacletDir, "Libraries", "Grasshopper", "WolframGrasshopperSupport.dll"}],
            FileNameJoin[{$deployDir, "WolframGrasshopperSupport.dll"}],
            OverwriteTarget -> True
        ];
    ]
    

(**********************************  GHDeploy  *********************************)

GHDeploy::param:= "The parameter type `1` is not currently supported."

Options[GHDeploy] = {SaveDefinitions -> True, Initialization -> None, "Description" -> "User-generated Wolfram Language computation",  "Icon" -> Automatic}

(* These two defs allow users who are calling funcs with just one input or one output to leave off the outer wrapping braces. *)
GHDeploy[name_, func_, inputSpec_, outputSpec:{_String, _String, _String, _String, _}, opts:OptionsPattern[]] :=
    GHDeploy[name, func, inputSpec, {outputSpec}, opts]

GHDeploy[name_, func_, inputSpec:{_String, _String, _String, _String, _}, outputSpec_, opts:OptionsPattern[]] :=
    GHDeploy[name, func, {inputSpec}, outputSpec, opts]

(* Maybe the param spec should be "Text" -> {name, nick, desc, etc...}. Or maybe options for all values? *)
GHDeploy[name_String, func_, inputSpec:{{_String, _String, _String, _String, __}...},
                       outputSpec:{{_String, _String, _String, _String, _}..}, OptionsPattern[]] :=
    Module[{codeString, asmPath, saveDefs, initialization, icon, desc, componentGuid},
        {saveDefs, initialization, icon, desc} = OptionValue[{SaveDefinitions, Initialization, "Icon", "Description"}];
        If[icon === Automatic, icon = name];
        (* Fail right away if func is not of the correct form. Must be symbol or pure function. *)
        If[Head[func] =!= Symbol && Head[func] =!= Function,
            Message[GHDeploy::badfunc];
            Return[$Failed]
        ];
        componentGuid = CreateUUID[];
        (* TODO: Verify that all user-specified types are supported. *)
        codeString =
            TemplateApply[
                FileTemplate[FileNameJoin[{$thisPacletDir, "Files", "Component.cs"}]],
                <|"Name" -> name, "Nickname" -> name,  "Category" -> "Wolfram",
                  "Subcategory" -> "Extensions", "Description" -> desc,
                  "GUID" -> componentGuid,
                  "RegisterInputParams" -> StringJoin[addParam /@ inputSpec], 
                  "RegisterOutputParams" -> StringJoin[addParam /@ outputSpec],
                  "GetData" -> StringJoin[MapIndexed[getData, inputSpec]],
                  "InputArgCount" -> ToString[Length[inputSpec]],
                  "UseInit" -> If[initialization =!= None, "true", "false"],
                  "Initialization" -> If[initialization =!= None, ToString[initialization, InputForm], "\"\""],
                  "UseDefs" -> If[TrueQ[saveDefs], "true", "false"],
                  "Definitions" -> If[TrueQ[saveDefs], ToString[exprToStringWithSaveDefinitions[func, componentGuid], InputForm], ""],
                  "HeadIsSymbol" -> If[Head[func] === Symbol, "true", "false"],
                  "Func" -> ToString[func, InputForm],
                  "SendInputParams" -> StringJoin[MapIndexed[sendInputParam, inputSpec]],
                  "ReadAndStoreResults" -> StringJoin[MapIndexed[readAndStoreResult, outputSpec]]
                |>
            ];

        asmPath = generateComponentAssembly[name, codeString, icon];
        If[StringQ[asmPath],
            deployComponentAssembly[asmPath];
            Null,
        (* else *)
            $Failed
        ]
    ]
    
(* TODO: accessType for all of these (list/item). 
         Issue message on bad default value.
         Coalesce these into a single function; they are almost identical.       
*)

addParam[{"Text", name_String, nickname_String, description_String, accessType_, default:_:None}] :=
    Module[{},
        TemplateApply[StringTemplate["pManager.AddTextParameter(\"`Name`\", \"`Nickname`\", \"`Description`\", `Access` `Default`);\n"],
                <|"Name" -> name, "Nickname" -> nickname, "Description" -> description,
                  "Access" -> accessTypeName[accessType],
                  "Default" -> If[StringQ[default], ", " <> ToString[default, InputForm], ""]
                |>
        ]
    ]
    
addParam[{"Integer", name_String, nickname_String, description_String, accessType_, default:_:None}] :=
    Module[{},
        TemplateApply[StringTemplate["pManager.AddIntegerParameter(\"`Name`\", \"`Nickname`\", \"`Description`\", `Access` `Default`);\n"],
                <|"Name" -> name, "Nickname" -> nickname, "Description" -> description, 
                  "Access" -> accessTypeName[accessType],
                  "Default" -> If[IntegerQ[default], ", " <> ToString[default, InputForm], ""]
                |>
        ]
    ]
    
addParam[{"Number", name_String, nickname_String, description_String, accessType_, default:_:None}] :=
    Module[{},
        TemplateApply[StringTemplate["pManager.AddNumberParameter(\"`Name`\", \"`Nickname`\", \"`Description`\", `Access` `Default`);\n"],
                <|"Name" -> name, "Nickname" -> nickname, "Description" -> description,
                  "Access" -> accessTypeName[accessType],
                  "Default" -> If[NumberQ[default], ", " <> ToString[N[default], InputForm], ""]
                |>
        ]
    ]
    
addParam[{"Boolean", name_String, nickname_String, description_String, accessType_, default:_:None}] :=
    Module[{},
        TemplateApply[StringTemplate["pManager.AddBooleanParameter(\"`Name`\", \"`Nickname`\", \"`Description`\", `Access` `Default`);\n"],
                <|"Name" -> name, "Nickname" -> nickname, "Description" -> description,
                  "Access" -> accessTypeName[accessType],
                  "Default" -> If[NumberQ[default], ", " <> ToString[N[default], InputForm], ""]
                |>
        ]
    ]
    
addParam[{"Any", name_String, nickname_String, description_String, accessType_, default:_:None}] :=
    Module[{},
        TemplateApply[StringTemplate["pManager.AddGenericParameter(\"`Name`\", \"`Nickname`\", \"`Description`\", `Access` `Default`);\n"],
                <|"Name" -> name, "Nickname" -> nickname, "Description" -> description,
                  "Access" -> accessTypeName[accessType],
                  "Default" -> "" (* No support for a default value in AddGenericParameter. *)
                |>
        ]
    ]
        
addParam[{"Expr", name_String, nickname_String, description_String, accessType_, default:_:None}] :=
    Module[{},
        TemplateApply[
            StringTemplate[
                "pManager.AddParameter(new ExprParam(), \"`Name`\", \"`Nickname`\", \"`Description`\", `Access` `Default`);\n"
            ],
            <|"Name" -> name, "Nickname" -> nickname, "Description" -> description,
              "Access" -> accessTypeName[accessType],
              "Default" -> "" (* No support for a default value in AddParameter. *)
            |>
        ]
    ]
    
addParam[{unsupported_String, nickname_String, description_String, accessType_, default:_:None}] :=
    (Message[GHDeploy::param, unsupported]; $Failed)


accessTypeName[sym_Symbol] := accessTypeName[SymbolName[sym]]

accessTypeName[type_String] :=
    Switch[type,
        "Tree", "GH_ParamAccess.tree",
        "List", "GH_ParamAccess.list",
        _, "GH_ParamAccess.item"
    ]
    

argDeclaration["Text", argName_, "GH_ParamAccess.item"] := "string " <> argName <> " = null;\n"
argDeclaration["Integer", argName_, "GH_ParamAccess.item"] := "int " <> argName <> " = 0;\n"
argDeclaration["Number", argName_, "GH_ParamAccess.item"] := "double " <> argName <> " = 0.0;\n"
argDeclaration["Boolean", argName_, "GH_ParamAccess.item"] := "bool " <> argName <> " = false;\n"
argDeclaration["Any", argName_, "GH_ParamAccess.item"] := "object " <> argName <> " = null;\n"
argDeclaration["Expr", argName_, "GH_ParamAccess.item"] := "ExprType " <> argName <> " = null;\n"
argDeclaration[_, argName_, "GH_ParamAccess.list"] := "List<IGH_Goo> " <> argName <> " = new List<IGH_Goo>();\n"
argDeclaration[_, argName_, "GH_ParamAccess.tree"] := "GH_Structure<IGH_Goo> " <> argName <> " = new GH_Structure<IGH_Goo>();\n"

getData[{type_, name_, nick_, desc_, accessType_, default:_:None}, {index_Integer}] := 
    Module[{argName = "arg" <> ToString[index]},
        argDeclaration[type, argName, accessTypeName[accessType]] <>
        Switch[accessTypeName[accessType],
            "GH_ParamAccess.list",
                TemplateApply[
                    StringTemplate[
                        "if (!DA.GetDataList(`indexMinusOne`, `argName`)) return;\n"
                    ],
                    <|"argName" -> argName, "indexMinusOne" -> ToString[index-1]|>
                ],
            "GH_ParamAccess.tree",
                TemplateApply[
                    StringTemplate[
                        "if (!DA.GetDataTree(`indexMinusOne`, out `argName`)) return;\n"
                    ],
                    <|"argName" -> argName, "indexMinusOne" -> ToString[index-1]|>
                ],
            _, (* "GH_ParamAccess.item" *)
                TemplateApply[
                    StringTemplate[
                        "if (!DA.GetData(`indexMinusOne`, ref `argName`)) return;
                         if (`argName` == null) return;\n"
                    ],
                    <|"argName" -> argName, "indexMinusOne" -> ToString[index-1]|>
                ]
        ]
    ]


sendInputParam[inputSpec:{_String, _String, _String, _String, accessType_, ___}, {index_Integer}] :=
    Module[{},
        "Utils.SendInputParam(arg" <> ToString[index] <> ", link, " <> accessTypeName[accessType] <> ", false);\n"
    ]
    

readAndStoreResult[{type_String, _, _, _, accessType_}, {index_Integer}] :=
    "if (!Utils.ReadAndStoreResult(\"" <> type <> "\", " <> ToString[index-1] <> ", link, DA, " <> accessTypeName[accessType] <> ", this)) return;\n"


(*
    neutralContextBlock[expr] evalutes expr without any contexts on the context path,
    to ensure symbols are serialized including their context (except System` symbols).
*)
Attributes[neutralContextBlock] = {HoldFirst};
neutralContextBlock[expr_] := Block[{$ContextPath = {"System`"}, $Context = "System`"}, expr]

(* Borrowed with some simplifications from internal code in the CloudObject package. *)
exprToStringWithSaveDefinitions[expr_, componentGuid_String] :=
    Module[{contextsToExclude, rhinoObjectParentContexts, shortContextsToExclude, defs, defsString, exprLine},
        (* Purely as an optimization, we want to avoid capturing defs from a number of contexts. Thee include contexts that
           form the implementation of RhinoLink itself, and contexts that come from LoadNETType on Rhino/Grasshopper classes
           (in both long and short form, in .NET/Link terminology).
           Note that Language`FullDefinition expects contexts to be given without the ending ` mark.
        *)
        rhinoObjectParentContexts = {"Rhino", "Grasshopper", "GHUIO"};
        (* To find the so-called short contexts, we take all contexts that start with one of the rhinoObjectParentContexts,
           and strip them down to their last context element.
        *)
        shortContextsToExclude = Last[StringSplit[#, "`"]]& /@ Catenate[Contexts[# <> "`*"] & /@ rhinoObjectParentContexts];
        contextsToExclude = Join[
            {"RhinoLink", "Wolfram`Rhino", "WolframScriptingPlugIn"},
            rhinoObjectParentContexts,
            shortContextsToExclude,
            OptionValue[Language`ExtendedFullDefinition, "ExcludedContexts"]
        ];
        defs = Language`ExtendedFullDefinition[expr, "ExcludedContexts" -> contextsToExclude];
        (* This final step is important (see RHINO-17). We want to prevent capturing defs for functions that are as yet
           undefined. There is no use in capturing the state of such functions, and it leads to serious bugs, because the
           common case is a static method def for a .NET object. The type might not be loaded into the kernel at GHDeploy
           time, so there are no rules for the symbol, but the code of the user function for the component will load the type on
           first use. Then upon second use, the no-defs state for the function would be restored by the re-loading of the
           captured defs, breaking the component.
        *)
        defs = DeleteCases[defs, HoldForm[_Symbol] -> {(_ -> {})..}];
        defsString =
            If[defs =!= Language`DefinitionList[],
                StringJoin[
                    "If[!TrueQ[RhinoLink`Private`alreadyLoadedInThisSession[\"" <> componentGuid <> "\"]],",
                    "RhinoLink`Private`alreadyLoadedInThisSession[\"" <> componentGuid <> "\"] = True;", 
                    neutralContextBlock[With[{d = defs},
                        (* Language`ExtendedFullDefinition[] can be used as the LHS of an assignment to restore all definitions. *)
                        ToString[Unevaluated[Language`ExtendedFullDefinition[] = d], InputForm,
                            CharacterEncoding -> "PrintableASCII"]
                    ]], 
                    "];\n"
                ],
            (* else *)
                ""
            ];
        exprLine = neutralContextBlock[ToString[Unevaluated[expr], InputForm, CharacterEncoding -> "PrintableASCII"]];
        StringTrim[defsString <> exprLine] <> "\n"
    ]


$filledRightTriangle = ToString[\[FilledRightTriangle]];

generateComponentAssembly[componentName_String, code_String, icon_] :=
NETBlock[
    Module[{provider, providerOptions, params, compilerResults, err, ct, scode, resFile},
     
        resFile = generateResourcesFile[icon];

        providerOptions = NETNew["System.Collections.Generic.Dictionary`2[string, string]"];
        providerOptions@Add["CompilerVersion", "v4.0"];
        provider = NETNew["Microsoft.CSharp.CSharpCodeProvider", providerOptions];
		  
        params = NETNew["System.CodeDom.Compiler.CompilerParameters"];
        params @ ReferencedAssemblies @ Add["System.dll"];
        params @ ReferencedAssemblies @ Add["System.Core.dll"];
        params @ ReferencedAssemblies @ Add["System.Drawing.dll"];
        params @ ReferencedAssemblies @ Add["System.Windows.Forms.dll"];
        params @ ReferencedAssemblies @ Add[FileNameJoin[{$GrasshopperHome, "GH_IO.dll"}]];
        params @ ReferencedAssemblies @ Add[FileNameJoin[{$GrasshopperHome, "Grasshopper.dll"}]];
        params @ ReferencedAssemblies @ Add[FileNameJoin[{$RhinoHome, "System", "rhinocommon.dll"}]];
        params @ ReferencedAssemblies @ Add[FileNameJoin[{$thisPacletDir, "Libraries", "Rhino", "Wolfram.NETLink.dll"}]];
        params @ ReferencedAssemblies @ Add[FileNameJoin[{$thisPacletDir, "Libraries", "Grasshopper", "WolframGrasshopperSupport.dll"}]];
		  
        params@EmbeddedResources@Add[resFile];
        params@GenerateInMemory = False;
        params@OutputAssembly = FileNameJoin[{$TemporaryDirectory, componentName <> ".gha"}];
		
		compilerResults = provider@CompileAssemblyFromSource[params, {code}];
        provider@Dispose[];
        DeleteFile[resFile];
		  
        err = compilerResults@Errors;
        ct = err@Count;
        If[ct > 0,
            scode = StringSplit[code, "\n"];
            Print["number of errors = ", ct];
            Print[ 
                "Error: ",
                err[#]@ErrorText,
                "\nLine: ",
                err[#]@Line,
                "\n",
                StringJoin @ 
                    Insert[Characters[scode[[err[#]@Line]]], 
                    $filledRightTriangle, err[#]@Column]
            ]& /@ Range[0, ct - 1];
            Return[$Failed]
        ];
        
        compilerResults@PathToAssembly
    ]
]


generateResourcesFile[icon_] :=
    NETBlock[
        Module[{iconGraphic, iconData, resWriter, resFile},
            resFile = FileNameJoin[{$TemporaryDirectory, "gh.resources"}];
            (* prepare icon file. *)
            If[Head[icon] === Graphics,
                (* If it's already a Graphics, resize to 24x24. *)
                iconGraphic = ImageResize[icon, {24, 24}],
            (* else *)
                iconGraphic = Graphics[{Text[Style[icon, {Bold, Larger}]]}, ImageSize->{24,24}]
            ];
            iconData = ToCharacterCode[ExportString[iconGraphic, "PNG"]];
            resWriter = NETNew["System.Resources.ResourceWriter", resFile];
            resWriter@AddResource["Icon", MakeNETObject[iconData, "System.Byte[]"]];
            resWriter@Close[];
            resFile
        ]
    ]
 
 
deployComponentAssembly[assemblyPath_String] :=
    Module[{asmName},
        asmName = FileNameTake[assemblyPath];
        If[FileExistsQ[FileNameJoin[{$deployDir, asmName}]],
            DeleteFile[FileNameJoin[{$deployDir, asmName}]]
        ];
        CopyFile[assemblyPath, FileNameJoin[{$deployDir, asmName}]];
        (* Copy needed libraries if they are not already present. *)
        If[!FileExistsQ[FileNameJoin[{$deployDir, "WolframGrasshopperSupport.dll"}]],
            CopyFile[FileNameJoin[{$thisPacletDir, "Files", "WolframGrasshopperSupport.dll"}], FileNameJoin[{$deployDir, "WolframGrasshopperSupport.dll"}]]
        ];
        If[!FileExistsQ[FileNameJoin[{$deployDir, "WolframGrasshopperComponents.gha"}]],
            CopyFile[FileNameJoin[{$thisPacletDir, "Files", "WolframGrasshopperComponents.gha"}], FileNameJoin[{$deployDir, "WolframGrasshopperComponents.gha"}]]
        ];
        If[!FileExistsQ[FileNameJoin[{$deployDir, "Wolfram.NETLink.dll"}]],
            CopyFile[FileNameJoin[{$thisPacletDir, "Files", "Wolfram.NETLink.dll"}], FileNameJoin[{$deployDir, "Wolfram.NETLink.dll"}]]
        ];
        If[!FileExistsQ[FileNameJoin[{$deployDir, "ml32i4.dll"}]],
            CopyFile[FileNameJoin[{$thisPacletDir, "Files", "ml32i4.dll"}], FileNameJoin[{$deployDir, "ml32i4.dll"}]]
        ];
        If[!FileExistsQ[FileNameJoin[{$deployDir, "ml64i4.dll"}]],
            CopyFile[FileNameJoin[{$thisPacletDir, "Files", "ml64i4.dll"}], FileNameJoin[{$deployDir, "ml64i4.dll"}]]
        ]
    ]
    
    
    
(* Called from C# Wolfram script. Sets up the link from a launched kernel that waits for an FE to attach. *)
setupRhinoAttachLink[] :=
    Module[{link},
        debug["Entering setuplinksfromunity"];
        link = LinkCreate["RhinoAttach"];
        If[Head[link] === LinkObject,
            MathLink`AddSharingLink[link, MathLink`SendInputNamePacket -> True]
        ];
        debug["attach: " <> ToString[link]];
        
        debug["at start, previous link was : " <> ToString[$previousLink]];
        If[Head[$previousLink] === LinkObject,
            (* Typically, was already closed in unityDetach[] from last session. *)
            MathLink`RemoveSharingLink[$previousLink];
            LinkClose[$previousLink];
            debug["just closed " <> ToString[$previousLink]]
        ];
        
        (*prepareLinkForUnityToConnect[];*)
        
        $previousLink = $ParentLink;
        debug["link waiting for next time: " <> ToString[link]];
        debug["current link, which wil lbe closed next time " <> ToString[$previousLink]];
        
        (* It is important to make preemptive all the links that could get U-to-M traffic. Otherwise it is easy
           to get deadlock when calling from Wolfram into Unity at the same time a user script is calling
           into Wolfram.
        *)
        MathLink`AddSharingLink[$ParentLink, MathLink`AllowPreemptive -> True];
    ]
    
    
    (* Called from C# Wolfram script *)
setupReaderLink[] :=
    (
        $readerLink = LinkCreate[];
        LinkWrite[$ParentLink, First[$readerLink]];
        LinkConnect[$readerLink];
        NETLink`InstallNET`Private`$nlink = $readerLink;
        NETLink`InstallNET`Private`$uilink = $ParentLink;
    )



(* 
 * Data Type Conversions
 *)


FromRhino[obj_Symbol] :=
	FromRhino[obj, obj@GetType[]@ToString[]]


FromRhino[objs_List] :=
	FromRhino /@ objs


FromRhino[objs_List, {type_}] :=
	FromRhino[#, type]& /@ objs


FromRhino[_, type_] :=
	$Failed[type]


ToRhino[expr_] :=
	ToRhino[expr, expr /. 
		(* default conversions *)
		{
			{_?NumericQ, _?NumericQ, _?NumericQ} -> "Rhino.Geometry.Point3d",
			{{_?NumericQ, _?NumericQ, _?NumericQ}..} -> {"Rhino.Geometry.Point3d"},
			_MeshRegion -> "Rhino.Geometry.Mesh",
			_BoundaryMeshRegion -> "Rhino.Geometry.Mesh",
			GraphicsComplex[{{_?NumericQ,_?NumericQ,_?NumericQ}...}, {_Polygon...}] -> "Rhino.Geometry.Mesh",
			_TransformationFunction -> "Rhino.Geometry.Transform"
		}
	]


ToRhino[expr:{___}, {type_}] :=
	ToRhino[#, type]& /@ expr


(* Rhino.Geometry.Transform *)


ToRhino[tf_TransformationFunction, "Rhino.Geometry.Transform"] :=
	Block[{m, t},
		m = TransformationMatrix[tf];
		t = NETNew["Rhino.Geometry.Transform", 1];
	
		t@M00 = m[[1,1]]; t@M01 = m[[1,2]]; t@M02 = m[[1,3]]; t@M03 = m[[1,4]];
		t@M10 = m[[2,1]]; t@M11 = m[[2,2]]; t@M12 = m[[2,3]]; t@M13 = m[[2,4]];
		t@M20 = m[[3,1]]; t@M21 = m[[3,2]]; t@M22 = m[[3,3]]; t@M23 = m[[3,4]];
		t@M30 = m[[4,1]]; t@M31 = m[[4,2]]; t@M32 = m[[4,3]]; t@M33 = m[[4,4]];

		t
	]


FromRhino[t_, "Rhino.Geometry.Transform"] :=
	{
		{t[M00], t[M01], t[M02], t[M03]},
		{t[M10], t[M11], t[M12], t[M13]},
		{t[M20], t[M21], t[M22], t[M23]},
		{t[M30], t[M31], t[M32], t[M33]}
	}


(* Rhino.Geometry.Vector3d *)


ToRhino[{x_, y_, z_}, "Rhino.Geometry.Vector3d"] :=
	NETNew["Rhino.Geometry.Vector3d", N[x], N[y], N[z]]


FromRhino[obj_, "Rhino.Geometry.Vector3d"] :=
	{obj@X, obj@Y, obj@Z}


(* Rhino.Geometry.Point3d *)


ToRhino[{x_, y_, z_}, "Rhino.Geometry.Point3d"] :=
	NETNew["Rhino.Geometry.Point3d", N[x], N[y], N[z]]


FromRhino[obj_, "Rhino.Geometry.Point3d"] :=
	{obj@X, obj@Y, obj@Z}


ToRhino[expr_, {"Rhino.Geometry.Point3d"}] :=
	Block[{},
		LoadNETType["Wolfram.Rhino.WolframScriptingPlugIn"];
		WolframScriptingPlugIn`ToRhinoPoint3dArray[expr]
	]


ToRhino[expr_, "Rhino.Geometry.Point3d[]"] :=
	Block[{},
		LoadNETType["Wolfram.Rhino.WolframScriptingPlugIn"];
		ReturnAsNETObject@WolframScriptingPlugIn`ToRhinoPoint3dArray[expr]
	]



(* ::Text:: *)
(*This cannot be wrapped with NETBlock to reclaim the Enumerator, or it will destroy the objects returned by the enumerator.*)


FromRhino[obj_, "Rhino.Geometry.Point3d[]"] := (* slow version *)
	Block[{enum = obj@GetEnumerator[]},
		Reap[While[enum@MoveNext[], Sow[FromRhino[enum@Current]]]][[2, 1]]
	]


(* Rhino.Geometry.Mesh *)


TriangulateFaces[faces_] :=
	faces /. Polygon[face_] :> Sequence @@ (Polygon[Prepend[#, First[face]]]& /@ Partition[Rest[face], 2, 1])


ToRhino[mesh_, "Rhino.Geometry.Mesh"] :=
	Block[{},
		LoadNETType["Wolfram.Rhino.WolframScriptingPlugIn"];
		Wolfram`Rhino`WolframScriptingPlugIn`ToRhinoMesh[
			MeshCoordinates[mesh],
			(First[#] - 1)& /@ TriangulateFaces[MeshCells[mesh, 2]]
		]
	]


ToRhino[GraphicsComplex[pts:{{_?NumericQ,_?NumericQ,_?NumericQ}...}, polygons:{_Polygon...}], "Rhino.Geometry.Mesh"] :=
	Block[{},
		LoadNETType["Wolfram.Rhino.WolframScriptingPlugIn"];
		Wolfram`Rhino`WolframScriptingPlugIn`ToRhinoMesh[
			pts,
			(First[#] - 1)& /@ polygons
		]
	]


FromRhino[obj_, "Rhino.Geometry.Mesh"] :=
	Block[{},
		LoadNETType["Wolfram.Rhino.WolframScriptingPlugIn"];
		MeshRegion[
			Wolfram`Rhino`WolframScriptingPlugIn`RhinoMeshVertices[obj],
			Polygon[Wolfram`Rhino`WolframScriptingPlugIn`RhinoMeshFaces[obj]]
		]
	]


(* Rhino.DocObjects.CurveObject *)


FromRhino[obj_, "Rhino.DocObjects.CurveObject"] :=
	FromRhino[obj@Geometry]


(* Rhino.Geometry.NurbsCurve *)


FromRhino[obj_, "Rhino.Geometry.NurbsCurve"] :=
	Block[{degree, nControlPoints, controlPoints, nKnots, knots},
		degree = obj@Degree;
		nControlPoints = obj@Points@Count;
		controlPoints = {#@X,#@Y,#@Z}& /@ Table[obj@Points@Item[i]@Location,{i, 0, nControlPoints-1}];
		nKnots=obj@Knots@Count;
		knots = Table[obj@Knots@Item[i], {i, 0, nKnots-1}];
		BSplineCurve[
			controlPoints,
			SplineDegree->degree,
			SplineKnots->Join[{First[knots]}, knots, {Last[knots]}]
		]
	]


(* Rhino.Geometry.LineCurve *)


FromRhino[obj_, "Rhino.Geometry.LineCurve"] :=
	Line[{FromRhino@obj@PointAtStart, FromRhino@obj@PointAtEnd}]


(* Rhino.Geometry.PolylineCurve *)


FromRhino[obj_, "Rhino.Geometry.PolylineCurve"] :=
	Line[Table[FromRhino@obj@Point[i],{i,0,obj@PointCount-1}]]


(* Rhino.Geometry.PolyCurve *)


FromRhino[obj_, "Rhino.Geometry.PolyCurve"] :=
	GraphicsGroup[FromRhino/@ Table[obj@SegmentCurve[i], {i, 0, obj@SegmentCount-1}]]


(* 
 * Queries
 *)


(* ::Text:: *)
(*This cannot be wrapped with NETBlock to reclaim the Enumerator, or it will destroy the objects returned by the enumerator.*)


RhinoActiveDoc[] :=
	 Block[{},
		LoadNETType["Rhino.RhinoDoc"];
		RhinoDoc`ActiveDoc
	 ]

RhinoDocObjects[] := RhinoDocObjects[RhinoActiveDoc[]]
RhinoDocObjects[doc_]:=
	With[{it = doc@Objects@GetEnumerator[]},
		Flatten[Reap[While[it@MoveNext[], Sow[it@Current]]][[2]]]
	]


(* 
 * Rhino Geometric Operations 
 *)


RhinoMeshUnion[meshes__Symbol]:=
	RhinoMeshUnion[{meshes}]


RhinoMeshUnion[meshes1_List, meshes2_List]:=
	RhinoMeshUnion[Flatten[Join[{meshes1}, {meshes2}]]]


RhinoMeshUnion[meshes_List]:=
	Rhino`Geometry`Mesh`CreateBooleanUnion[
		MakeNETObject[meshes,"Rhino.Geometry.Mesh[]"]
	]


RhinoMeshDifference[mesh_Symbol, meshes__Symbol]:=
	RhinoMeshDifference[{mesh}, {meshes}]


RhinoMeshDifference[meshes1_List, meshes2_List]:=
	Rhino`Geometry`Mesh`CreateBooleanDifference[
		MakeNETObject[meshes1,"Rhino.Geometry.Mesh[]"],
		MakeNETObject[meshes2,"Rhino.Geometry.Mesh[]"]
	]


RhinoMeshIntersection[mesh_Symbol, meshes__Symbol]:=
	RhinoMeshIntersection[{mesh}, {meshes}]


RhinoMeshIntersection[meshes1_List, meshes2_List]:=
	Rhino`Geometry`Mesh`CreateBooleanIntersection[
		MakeNETObject[meshes1,"Rhino.Geometry.Mesh[]"],
		MakeNETObject[meshes2,"Rhino.Geometry.Mesh[]"]
	]


(* 
 * Other Rhino Operations 
 *)


RhinoAdd[obj_Symbol] :=
	{RhinoActiveDoc[]@Objects@Add[obj]}


(* ::Text:: *)
(*These should just be listable, but there seemed to be an efficiency penalty; revisit.*)


RhinoAdd[objs_List] :=
	Flatten[RhinoActiveDoc[]@Objects@Add[#]& /@ objs]


NETRelease[obj_Symbol] :=
	ReleaseNETObject[obj]


NETRelease[objs_List] :=
	ReleaseNETObject /@ objs


RhinoShow[obj_] :=
	Block[{guids},
		guids = RhinoAdd[obj];
		NETRelease[obj];
		RhinoActiveDoc[]@Views@Redraw[];
		guids
	]


RhinoDelete[guid_Symbol] :=
	RhinoActiveDoc[]@Objects@Delete[guid, True]


RhinoDelete[guids_List] :=
	RhinoActiveDoc[]@Objects@Delete[#, True]& /@ guids


RhinoUnshow[guid_] :=
	Block[{},
		RhinoDelete[guid];
		RhinoActiveDoc[]@Views@Redraw[];
	]


RhinoReshow[guid_, obj_] :=
	Block[{guids},
		RhinoDelete[guid];
		guids = RhinoAdd[obj];
		NETRelease[obj];
		RhinoActiveDoc[]@Views@Redraw[];
		guids
	]


End[]

EndPackage[]

