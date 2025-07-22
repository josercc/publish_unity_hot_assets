import 'package:get/get.dart' hide Response;
import 'package:dio/dio.dart';

GlobalServer get global => Get.find();

class GlobalServer extends GetxService {
  final dio = Dio();

  String? token;

  Future<Response<T>> post<T>({
    required String path,
    required Map<String, dynamic> data,
  }) async {
    final url = _url(path);
    final res = await dio.post<T>(
      url,
      data: data,
      options: Options(
        headers: {
          'x-access-token': token,
        },
      ),
    );
    print(res.data);
    return res;
  }

  String _url(String path) {
    return 'http://frontmanager-sit.winnerapp.cn:8000$path';
  }
}
