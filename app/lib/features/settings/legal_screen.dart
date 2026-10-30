import 'package:flutter/material.dart';

/// 条款与隐私：用户协议 / 隐私政策 / 儿童个人信息保护规则
/// 内容对应本 App 的实际数据处理方式（游客数据仅存本机、账号数据上云、
/// 注销即物理删除、埋点匿名）。
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.initialTab = 0});

  /// 0 = 用户协议，1 = 隐私政策，2 = 儿童个人信息保护规则
  final int initialTab;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF1C1C1E);
  static const _gray = Color(0xFF8E8E93);
  static const _pink = Color(0xFFF27A8D);

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '条款和隐私',
          style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: _ink),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _pink,
          unselectedLabelColor: _gray,
          indicatorColor: _pink,
          labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13.5),
          tabs: const [
            Tab(text: '用户协议'),
            Tab(text: '隐私政策'),
            Tab(text: '儿童保护规则'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _LegalText(_userAgreement),
          _LegalText(_privacyPolicy),
          _LegalText(_childrenPolicy),
        ],
      ),
    );
  }
}

class _LegalText extends StatelessWidget {
  const _LegalText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF3A3A3C),
          fontSize: 13,
          height: 1.75,
        ),
      ),
    );
  }
}

const _updated = '更新日期：2026 年 10 月 30 日\n生效日期：2026 年 10 月 30 日\n适用版本：吨吨 v1.0.0 及以后版本\n\n';

const _userAgreement = '$_updated'
    '欢迎使用「吨吨」。本协议是你与本 App 运营方之间关于使用本服务的约定。'
    '你注册账号、登录或继续使用本 App，即表示你已阅读并同意本协议。\n\n'
    '一、服务内容\n'
    '本 App 提供饮水记录、每日目标、连续打卡、角色养成、桌面小组件、'
    '会员服务与积分兑换等功能。部分功能（如云同步、会员、积分）需要登录账号并联网使用；'
    '未登录时可以使用本机记录等基础功能。\n\n'
    '二、账号\n'
    '1. 你可以使用邮箱注册并登录。你应保证注册信息真实、合法，并对账号下的行为负责。\n'
    '2. 同一账号在同一时间仅允许一台设备保持登录状态。在新设备登录会使旧设备的登录失效，'
    '旧设备将回到未登录状态，本机数据仍会保留。\n'
    '3. 你可以在 App 内永久注销账号。注销后，该账号的云端数据（饮水记录、设置、积分、'
    '会员申请与订单信息、头像等）将被删除且无法恢复；本机中属于该账号的缓存数据也会同时清除。\n\n'
    '三、用户行为规范\n'
    '你不得利用本 App 从事违法活动，不得通过技术手段批量注册、伪造数据、刷取积分或会员权益，'
    '不得干扰服务正常运行。我们有权对异常账号采取限制功能、冻结或注销等措施。\n\n'
    '四、会员与积分\n'
    '1. 当前为内测阶段，会员开通通过提交申请、由运营人工确认后生效，无需付款。\n'
    '2. 积分通过消消乐等任务获得，仅限已登录账号使用，可用于兑换会员天数；'
    '积分不可转让、不可提现。游客（未登录）状态不计积分。\n'
    '3. 正式版如接入应用内购买，将按对应平台（App Store / Google Play）的规则执行。\n\n'
    '五、免责与责任限制\n'
    '饮水目标与提醒仅作为健康习惯辅助建议，不构成医疗意见。因设备、网络、系统限制'
    '（如后台限制、通知权限被关闭）导致提醒延迟或数据同步延迟的，我们会尽力修复，'
    '但不承担由此产生的间接损失。\n\n'
    '六、协议的变更与终止\n'
    '我们可能根据功能调整更新本协议，更新后会在 App 内展示。若你不同意更新内容，'
    '可以停止使用并注销账号；继续使用视为接受更新后的协议。\n\n'
    '七、联系我们\n'
    '如对本协议有疑问，可通过 App 内「设置 - 意见反馈」联系我们。\n';

const _privacyPolicy = '$_updated'
    '我们重视你的个人信息保护。本政策说明我们收集哪些信息、如何使用与保存，以及你享有的权利。\n\n'
    '一、我们收集的信息\n'
    '1. 账号信息：注册与登录时收集邮箱、密码（仅保存加密后的哈希值，不保存明文）、昵称；'
    '你主动上传头像时，会保存头像图片。\n'
    '2. 健康与习惯信息：你记录的饮品、容量、饮水时间、每日目标、体重、性别、'
    '提醒时间与重置时刻等设置。这些信息用于展示统计、计算完成度与生成提醒。\n'
    '3. 会员与积分信息：会员开通申请（套餐、状态、订单号、创建与支付时间）、'
    '积分余额与获取/消耗流水。\n'
    '4. 设备与日志信息：App 版本、系统版本、设备型号、崩溃堆栈与操作事件，'
    '用于排查故障和改进产品；此类统计默认使用匿名标识，不包含邮箱等直接身份信息。\n'
    '5. 反馈信息：你在意见反馈中主动填写的内容与联系方式。\n\n'
    '二、信息的存储位置与期限\n'
    '1. 未登录（游客）时，饮水记录与设置仅保存在你的手机本地，不会上传到服务器；'
    '卸载 App 或清除应用数据会导致这部分数据丢失。\n'
    '2. 登录后，账号相关数据保存在中国境内的服务器，用于多设备同步。'
    '数据保存至你主动注销账号为止；注销会物理删除账号及其关联数据（依法需要留存的除外）。\n'
    '3. 匿名统计信息不含直接身份标识，仅用于产品改进。\n\n'
    '三、信息的使用与共享\n'
    '我们不会出售你的个人信息，也不会将其用于本政策未说明的用途。'
    '仅在以下情形下共享：为提供云存储、短信/推送等基础服务而使用的云服务商；'
    '法律法规要求或司法机关依法要求提供时。\n\n'
    '四、你的权利\n'
    '1. 你可以随时查看和修改昵称、头像、目标、提醒等设置。\n'
    '2. 你可以随时注销账号，注销后云端数据将被删除；本机游客数据不受影响。\n'
    '3. 你可以在系统设置中关闭通知权限、撤销相册等权限，这不会影响基础记录功能。\n\n'
    '五、权限说明\n'
    '通知权限用于饮水提醒与连续打卡提醒；精确闹钟权限用于准点提醒；'
    '相册/相机权限仅在你主动更换头像时使用；网络权限用于账号登录、云同步、'
    '内容更新与匿名统计。\n\n'
    '六、未成年人保护\n'
    '若你是未满 14 周岁的儿童，请在监护人陪同下阅读本政策，并在取得监护人同意后使用。'
    '详见「儿童保护规则」。\n\n'
    '七、政策更新与联系\n'
    '本政策更新后会在 App 内展示。如有疑问或需要行使上述权利，'
    '可通过「设置 - 意见反馈」联系我们，我们会在 15 个工作日内答复。\n';

const _childrenPolicy = '$_updated'
    '本规则适用于未满 14 周岁的儿童用户，是《隐私政策》的补充。\n\n'
    '一、监护人同意\n'
    '儿童使用本 App 前，应由监护人阅读并同意《用户协议》《隐私政策》及本规则。'
    '监护人可以帮助儿童完成注册、设置每日目标与提醒时间。\n\n'
    '二、我们收集的儿童信息\n'
    '仅在实现功能所必需的范围内收集：邮箱（用于登录）、昵称、头像（可选）、'
    '饮水记录、每日目标与提醒设置、会员申请信息。我们不会收集儿童的位置、通讯录、'
    '人脸等敏感信息，也不会向儿童推送个性化广告。\n\n'
    '三、信息的使用与保存\n'
    '儿童信息仅用于饮水记录、统计与提醒功能，保存于中国境内服务器，'
    '至账号注销为止。未登录时数据仅保存在本机。\n\n'
    '四、监护人的权利\n'
    '监护人可通过「设置 - 意见反馈」联系我们，查询、更正或删除儿童的个人信息，'
    '也可以直接在 App 内注销账号。我们核实身份后会在 15 个工作日内处理。\n\n'
    '五、其他\n'
    '本规则未说明的事项，适用《隐私政策》。如本规则与《隐私政策》不一致，'
    '以本规则为准。\n';
