/// 示範題組：從空白（沒有任何特徵）開始，依序問完一組問題，推薦會穩定落到 [expect]。
///
/// App 的帳戶頁「示範題組」用這份清單自動提問；
/// `flutter test tool/system_one/demo_scenarios_test.dart` 用真的 System One 從空白跑兩次，確認結果穩定。
/// 改了題目或推薦算法後，記得重跑那支腳本。
class DemoScenario {
  const DemoScenario({
    required this.name,
    required this.description,
    required this.questions,
    required this.expect,
  });

  final String name;

  /// 一句話說明這組會得到什麼推薦（顯示在選單上）。
  final String description;

  /// 依序要問小幫手的問題。
  final List<String> questions;

  /// 推薦位置 → 應該排第一的項目（包含這段文字即可）。
  final Map<String, String> expect;

  static const List<DemoScenario> all = [
    DemoScenario(
      name: '開車族',
      description: '訂閱推薦停車費通知、熱門繳費停車費第一',
      questions: ['繳停車費', '附近哪裡好停車', '路邊停車費逾期了怎麼辦'],
      expect: {
        '訂閱推薦': '停車費通知',
        '熱門繳費': '停車費',
        '首頁大圖': '停車費',
        '小幫手建議': '繳停車費',
      },
    ),
    DemoScenario(
      name: '帶小孩的家長',
      description: '熱門繳費學雜費第一、首頁大圖親子館、活動動物園夜間',
      questions: ['想帶小孩去放電', '小孩的學費要怎麼繳', '親子館要預約嗎'],
      expect: {
        '熱門繳費': '學雜費',
        '首頁大圖': '親子館',
        '活動訊息': '動物園夜間',
        '小幫手建議': '動物園怎麼去',
      },
    ),
    DemoScenario(
      name: '愛看書',
      description: '訂閱推薦圖書到期通知、首頁大圖閱讀馬拉松、我的服務圖書借閱',
      questions: ['我想借書', '圖書館的書可以續借嗎', '最近有什麼閱讀活動'],
      expect: {
        '訂閱推薦': '圖書到期通知',
        '首頁大圖': '閱讀馬拉松',
        '你可能需要／我的服務': '圖書借閱',
        '小幫手建議': '我想借書',
      },
    ),
    DemoScenario(
      name: '外國觀光客（英文）',
      description: '訂閱推薦臺北旅遊網、活動好玩卡第一',
      questions: ['Where can I see pandas?', 'How do I get to Taipei 101?', 'Is there a travel pass for tourists?'],
      expect: {
        '訂閱推薦': '臺北旅遊網最新消息',
        '活動訊息': '好玩卡',
        '小幫手建議': '附近有什麼',
      },
    ),
    DemoScenario(
      name: '關心防災',
      description: '訂閱推薦防汛資訊、首頁大圖防災包、建議問法颱風淹水通報',
      questions: ['颱風天家裡淹水', '颱風要來了家裡要準備什麼', '颱風天會不會停班停課'],
      expect: {
        '訂閱推薦': '防汛資訊',
        '首頁大圖': '防災包',
        '小幫手建議': '颱風淹水通報',
      },
    ),
  ];
}
