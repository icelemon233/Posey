import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image;
import 'package:posey/core/json.dart';
import 'package:posey/features/poses/pose_template.dart';
import 'package:posey/features/ai_pose/ai_configuration.dart';

Uint8List resizeForAi(Uint8List bytes) {
  final decoded=image.decodeImage(bytes);if(decoded==null)throw const FormatException('无法读取这张图片');
  final oriented=image.bakeOrientation(decoded),largest=decoded.width>decoded.height?decoded.width:decoded.height;
  final resized=largest>2048?image.copyResize(oriented,width:oriented.width>=oriented.height?2048:null,height:oriented.height>oriented.width?2048:null):oriented;
  return Uint8List.fromList(image.encodeJpg(resized,quality:90));
}
Uint8List prepareGuide(({Uint8List bytes,bool mirrored}) input) {
  final bytes=resizeForAi(input.bytes);if(!input.mirrored)return bytes;
  return Uint8List.fromList(image.encodeJpg(image.flipHorizontal(image.decodeImage(bytes)!),quality:90));
}
class PreparedAiRequest {
  const PreparedAiRequest(this.configuration,this.body,this.title,{this.recoveryMetadata});
  final AiConfiguration configuration;
  final Json body;
  final String title;
  final Json? recoveryMetadata;
  PreparedAiRequest withRecoveryMetadata(Json metadata)=>PreparedAiRequest(configuration,body,title,recoveryMetadata:metadata);
  Json nativePayload()=>{'apiKey':configuration.normalizedKey,'endpoint':configuration.uri.toString(),'model':configuration.model,
    'sourceImage':(body['image'] as List)[0],'guideImage':(body['image'] as List)[1],'prompt':body['prompt'],'targetTitle':title,
    if(recoveryMetadata!=null)'metadata':recoveryMetadata};
}
abstract interface class AiPoseService {
  Future<PreparedAiRequest> prepare(AiConfiguration configuration,AiPreferences preferences,PoseTemplate target,Uint8List source);
  Future<Uint8List> generate(String jobId,PreparedAiRequest request);
  void cancel(String jobId);
}
abstract interface class AiResultDownloader {
  Future<Uint8List> downloadResult(String jobId,Uri uri);
}
class AiDownloadException implements Exception {
  const AiDownloadException(this.uri);
  final Uri uri;
  @override String toString()=>'成片下载中断。可以重试下载，无需再次生成。';
}
class ArkAiPoseService implements AiPoseService,AiConnectionTester,AiResultDownloader {
  ArkAiPoseService({http.Client Function()? clientFactory,Future<ByteData> Function(String)? assetLoader}):
    clientFactory=clientFactory??http.Client.new,assetLoader=assetLoader??rootBundle.load;
  final http.Client Function() clientFactory;
  final Future<ByteData> Function(String) assetLoader;
  final _clients=<String,http.Client>{};
  http.Client? _connection;
  @override void cancelConnectionCheck(){_connection?.close();_connection=null;}
  @override Future<PreparedAiRequest> prepare(AiConfiguration configuration,AiPreferences preferences,PoseTemplate target,Uint8List source) async {
    configuration.validate();final Uint8List guide;
    if(target.illustration.startsWith('assets/')){final data=await assetLoader(target.illustration);guide=data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes);}
    else{guide=await File(target.illustration).readAsBytes();}
    final sourceBytes=await compute(resizeForAi,source),guideBytes=await compute(prepareGuide,(bytes:guide,mirrored:target.mirrored));
    return PreparedAiRequest(configuration,{'model':configuration.model,'prompt':buildPosePrompt(target.title,preferences),
      'image':['data:image/jpeg;base64,${base64Encode(sourceBytes)}','data:image/jpeg;base64,${base64Encode(guideBytes)}'],
      'size':'2K','output_format':'jpeg','response_format':'b64_json','watermark':false},target.title);
  }
  Future<http.Response> _send(http.Client client,http.Request request,Duration timeout,{int limit=32*1024*1024}) => (() async {
    request.followRedirects=false;
    final response=await client.send(request);
    if((response.contentLength??0)>limit)throw StateError('服务返回的数据过大');
    final bytes=BytesBuilder(copy:false);var size=0;
    await for(final chunk in response.stream){size+=chunk.length;if(size>limit)throw StateError('服务返回的数据过大');bytes.add(chunk);}
    return http.Response.bytes(bytes.takeBytes(),response.statusCode,headers:response.headers,request:request);
  })().timeout(timeout);
  @override Future<Uint8List> generate(String jobId,PreparedAiRequest request) async {
    final client=clientFactory();_clients[jobId]=client;
    try {
      final message=http.Request('POST',request.configuration.uri)..headers.addAll({'Authorization':'Bearer ${request.configuration.normalizedKey}','Content-Type':'application/json'})..body=jsonEncode(request.body);
      final response=await _send(client,message,const Duration(minutes:5));
      Json payload={};try{payload=objectOf(jsonDecode(utf8.decode(response.bodyBytes)));}catch(_){/* Report the public status below. */}
      if(response.statusCode<200||response.statusCode>=300){
        final code='${objectOf(payload['error'])['code']??''}';
        if(response.statusCode==401||response.statusCode==403)throw StateError('AI 服务鉴权失败，请检查 API Key 和模型权限');
        if(response.statusCode==429)throw StateError('服务请求过多，请稍后再试');
        if(RegExp('sensitive|moderation',caseSensitive:false).hasMatch(code))throw StateError('当前画面无法生成，请换一个画面再试');
        if(response.statusCode==400)throw StateError('生成参数未被服务接受，请核对图像模型与服务地址');
        if(response.statusCode>=300&&response.statusCode<400)throw StateError('服务地址发生重定向，请填写最终的 HTTPS 地址');
        throw StateError('生成暂时失败，请稍后重试');
      }
      final data=payload['data'];if(data is! List||data.isEmpty)throw StateError('AI 没有返回可用图片');
      final item=objectOf(data.first);Uint8List bytes;
      if(item['b64_json'] is String){bytes=base64Decode(item['b64_json'] as String);}
      else if(item['url'] is String){final uri=Uri.parse(item['url']);if(uri.scheme!='https'||uri.userInfo.isNotEmpty)throw StateError('AI 返回的图片地址无效');
        try{final downloaded=await _send(client,http.Request('GET',uri),const Duration(seconds:45),limit:24*1024*1024);
          if(downloaded.statusCode!=200)throw StateError('download failed');bytes=downloaded.bodyBytes;
        }catch(_){throw AiDownloadException(uri);}
      }else{throw StateError('AI 没有返回可用图片');}
      if(image.decodeImage(bytes)==null)throw StateError('AI 返回的图片格式无效');
      return bytes;
    }finally{_clients.remove(jobId);client.close();}
  }
  Future<Uint8List> downloadResult(String jobId,Uri uri) async {
    if(uri.scheme!='https'||uri.userInfo.isNotEmpty)throw const FormatException('成片地址无效');
    final client=clientFactory();_clients[jobId]=client;
    try{final response=await _send(client,http.Request('GET',uri),const Duration(seconds:45),limit:24*1024*1024);
      if(response.statusCode!=200)throw StateError('成片暂时无法下载，请稍后重试下载。');
      if(image.decodeImage(response.bodyBytes)==null)throw StateError('成片图片格式无效');return response.bodyBytes;
    }finally{_clients.remove(jobId);client.close();}
  }
  @override void cancel(String jobId){_clients.remove(jobId)?.close();}
  @override Future<AiConnectionCheck> checkConnection(AiConfiguration configuration) async {
    configuration.validate();cancelConnectionCheck();final client=clientFactory();_connection=client;
    try {
      final request=http.Request('GET',configuration.baseUri.replace(path:'${configuration.baseUri.path}/models'))..headers['Authorization']='Bearer ${configuration.normalizedKey}';
      final response=await _send(client,request,const Duration(seconds:20),limit:4*1024*1024);
      if(response.statusCode==401||response.statusCode==403)throw StateError('密钥无效或没有模型访问权限');
      if(response.statusCode==404||response.statusCode==405)return const AiConnectionCheck('服务可以访问，但不提供模型列表。密钥与图像模型仍需在生成时验证。',[]);
      if(response.statusCode==429)throw StateError('服务请求过多，请稍后再试');
      if(response.statusCode!=200)throw StateError('连接检查失败（${response.statusCode}），请核对服务地址。');
      Json payload;try{payload=objectOf(jsonDecode(utf8.decode(response.bodyBytes)));}catch(_){throw const FormatException('服务未返回可识别的模型列表');}
      if(payload['data'] is! List)throw const FormatException('服务未返回可识别的模型列表');
      final models=(payload['data'] as List).map(objectOf).map((value)=>value['id']).whereType<String>().where((value)=>value.length<=200).take(1000).toList()..sort();
      final visible=models.contains(configuration.model.trim());
      return AiConnectionCheck(visible?'已连接，所选模型出现在服务返回的列表中。':'已连接，但列表中未找到所选模型。请核对模型 ID 或部署端点。',models,verified:visible);
    }finally{client.close();if(identical(_connection,client))_connection=null;}
  }
}
