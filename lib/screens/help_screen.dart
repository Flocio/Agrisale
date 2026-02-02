// lib/screens/help_screen.dart

import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('使用帮助', style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        )),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              title: '系统简介',
              icon: Icons.info_outline,
              color: Colors.blue,
              children: [
                _buildParagraph('Agrisale 是一款专业的农业销售管理系统，帮助您轻松管理产品库存、客户关系、采购销售等业务。系统支持多用户使用，每个用户的数据相互独立，确保数据安全。'),
                _buildParagraph('数据本地存储，保护您的隐私安全。'),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '基础信息管理',
              icon: Icons.inventory_2,
              color: Colors.green,
              children: [
                _buildSubSection('产品管理', [
                  _buildParagraph('• 添加产品：设置产品名称、描述、单位（支持：斤、公斤、袋、件、瓶）、供应商等信息'),
                  _buildParagraph('• 库存管理：系统会自动根据采购、销售、退货记录更新库存'),
                  _buildParagraph('• 产品编辑：可以随时修改产品信息，包括库存数量'),
                  _buildParagraph('• 产品筛选：支持按供应商筛选产品，方便快速查找'),
                  _buildParagraph('• 库存保护：系统会自动防止库存变为负数，确保数据准确性'),
                ]),
                _buildSubSection('客户管理', [
                  _buildParagraph('• 添加客户：记录客户姓名、联系方式等信息'),
                  _buildParagraph('• 客户列表：查看所有客户，支持编辑和删除'),
                  _buildParagraph('• 客户筛选：在销售、退货、进账等功能中可按客户筛选'),
                ]),
                _buildSubSection('供应商管理', [
                  _buildParagraph('• 添加供应商：记录供应商名称、联系方式等信息'),
                  _buildParagraph('• 供应商列表：查看所有供应商，支持编辑和删除'),
                  _buildParagraph('• 产品关联：每个产品可以关联一个供应商，方便管理采购来源'),
                ]),
                _buildSubSection('员工管理', [
                  _buildParagraph('• 添加员工：记录员工姓名等信息'),
                  _buildParagraph('• 经手人记录：在进账和汇款时可以选择经手人，便于追踪'),
                ]),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '业务功能',
              icon: Icons.shopping_cart,
              color: Colors.orange,
              children: [
                _buildSubSection('采购管理', [
                  _buildParagraph('• 添加采购：选择产品、供应商，输入数量、进价、采购日期'),
                  _buildParagraph('• 采购退货：数量输入负数即可记录采购退货（退货给供应商）'),
                  _buildParagraph('• 供应商筛选：可以先选择供应商，再选择该供应商的产品，提高录入效率'),
                  _buildParagraph('• 自动计算：系统自动计算总进价（进价 × 数量）'),
                  _buildParagraph('• 库存更新：采购后自动增加库存，采购退货自动减少库存，系统会自动防止库存变为负数'),
                ]),
                _buildSubSection('销售管理', [
                  _buildParagraph('• 添加销售：选择产品、客户，输入数量、单价、销售日期'),
                  _buildParagraph('• 供应商筛选：可按供应商筛选产品，方便快速选择'),
                  _buildParagraph('• 库存检查：销售时会检查库存是否充足，库存不足会提示，防止库存为负数'),
                  _buildParagraph('• 自动计算：系统自动计算总售价（单价 × 数量）'),
                  _buildParagraph('• 库存更新：销售后自动减少库存，系统会自动防止库存变为负数'),
                ]),
                _buildSubSection('退货管理', [
                  _buildParagraph('• 添加退货：选择产品、客户，输入数量、单价、退货日期'),
                  _buildParagraph('• 供应商筛选：可按供应商筛选产品'),
                  _buildParagraph('• 自动计算：系统自动计算总退款（单价 × 数量）'),
                  _buildParagraph('• 库存更新：退货后自动增加库存'),
                ]),
                _buildSubSection('进账管理', [
                  _buildParagraph('• 添加进账：记录客户付款信息'),
                  _buildParagraph('• 优惠管理：支持设置优惠金额或优惠前价格，系统自动计算另一个值'),
                  _buildParagraph('• 付款方式：支持现金、微信转账、银行卡三种付款方式'),
                  _buildParagraph('• 经手人：可选择员工作为经手人'),
                  _buildParagraph('• 日期默认：默认使用当天日期，可手动修改'),
                  _buildParagraph('• 退款记录：支持负数金额，用于记录客户退款，金额显示为绿色带正号'),
                  _buildParagraph('• 类型筛选：支持按"收款"或"退款"类型筛选进账记录'),
                ]),
                _buildSubSection('汇款管理', [
                  _buildParagraph('• 添加汇款：记录向供应商付款信息'),
                  _buildParagraph('• 付款方式：支持现金、微信转账、银行卡三种付款方式'),
                  _buildParagraph('• 经手人：可选择员工作为经手人'),
                  _buildParagraph('• 日期默认：默认使用当天日期，可手动修改'),
                  _buildParagraph('• 退款记录：支持负数金额，用于记录供应商退款，金额显示为绿色带正号'),
                  _buildParagraph('• 类型筛选：支持按"汇款"或"退款"类型筛选汇款记录'),
                ]),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '数据详情与日志',
              icon: Icons.history,
              color: Colors.indigo,
              children: [
                _buildSubSection('记录详情', [
                  _buildParagraph('• 查看详情：点击采购/销售/退货/进账/汇款记录可查看完整数据'),
                  _buildParagraph('• 操作历史：查看该记录的创建、修改、删除等操作历史'),
                  _buildParagraph('• 数据追溯：了解数据的完整变更过程，便于问题排查'),
                ]),
                _buildSubSection('实体详情', [
                  _buildParagraph('• 基础信息：点击产品/客户/供应商/员工可查看完整数据和操作历史'),
                  _buildParagraph('• 快捷导航：详情窗口中集成快捷按钮，可直接跳转到相关记录页面'),
                  _buildParagraph('• 客户/供应商：可快速查看对账单、往来记录、销售/采购记录'),
                  _buildParagraph('• 员工：可快速查看员工经手的进账和汇款记录'),
                  _buildParagraph('• 产品：可快速查看产品的交易记录'),
                ]),
                _buildSubSection('操作日志', [
                  _buildParagraph('• 日志记录：系统自动记录所有数据的创建、修改、删除操作'),
                  _buildParagraph('• 备份恢复日志：数据导入和备份恢复操作也会被记录'),
                  _buildParagraph('• 变更追踪：修改操作会记录变更前后的数据对比'),
                ]),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '报表统计',
              icon: Icons.bar_chart,
              color: Colors.purple,
              children: [
                _buildSubSection('基础统计', [
                  _buildParagraph('• 库存报表：查看所有产品的当前库存情况'),
                  _buildParagraph('• 采购报表：按日期范围查询采购记录，支持按产品、供应商筛选'),
                  _buildParagraph('• 销售报表：按日期范围查询销售记录，支持按产品、客户筛选'),
                  _buildParagraph('• 退货报表：按日期范围查询退货记录，支持按产品、客户筛选'),
                ]),
                _buildSubSection('综合分析', [
                  _buildParagraph('• 销售汇总：汇总销售数据，按产品、客户等维度统计'),
                  _buildParagraph('• 销售与进账：对比销售金额和实际进账，分析收款情况'),
                  _buildParagraph('• 采购与汇款：对比采购金额和实际汇款，分析付款情况'),
                  _buildParagraph('• 财务统计：综合财务数据分析，了解整体经营状况'),
                ]),
                _buildSubSection('智能分析', [
                  _buildParagraph('• 数据分析助手：使用 AI 技术分析您的业务数据'),
                  _buildParagraph('• 智能问答：可以询问销售趋势、库存情况、客户分析等问题'),
                  _buildParagraph('• 数据洞察：获得专业的业务建议和数据分析结果'),
                ]),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '数据导出',
              icon: Icons.file_download,
              color: Colors.teal,
              children: [
                _buildParagraph('• 导出格式：支持 CSV 和 PDF 两种格式'),
                _buildParagraph('• CSV 格式：适合在 Excel 等表格软件中打开和编辑'),
                _buildParagraph('• PDF 格式（新）：适合打印和分享，支持中文字体显示，自动生成美观的表格布局'),
                _buildParagraph('• 导出内容：包含报表数据、表头、汇总信息等完整内容'),
                _buildParagraph('• 保存方式：可以保存到本地文件，也可以直接分享给其他应用'),
                _buildParagraph('• 使用场景：适用于数据备份、报表打印、数据分析等需求'),
                _buildParagraph('• 格式选择：点击导出按钮后，先选择 CSV 或 PDF，再选择保存或分享'),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '系统设置',
              icon: Icons.settings,
              color: Colors.grey,
              children: [
                _buildSubSection('账户设置', [
                  _buildParagraph('• 修改密码：可以修改当前登录账户的密码'),
                  _buildParagraph('• 用户管理：多用户系统中，每个用户的数据相互独立'),
                ]),
                _buildSubSection('模型设置', [
                  _buildParagraph('• AI 模型配置：设置数据分析助手使用的 AI 模型'),
                  _buildParagraph('• API 密钥：配置 AI 服务的 API 密钥（如需要）'),
                ]),
                _buildSubSection('数据备份', [
                  _buildParagraph('• 手动备份：可以随时手动导出数据备份文件'),
                  _buildParagraph('• 自动备份：设置自动备份计划，定期备份数据'),
                  _buildParagraph('• 数据恢复：从备份文件恢复数据，保护数据安全'),
                ]),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '使用技巧',
              icon: Icons.lightbulb_outline,
              color: Colors.amber,
              children: [
                _buildParagraph('• 供应商筛选：在采购、销售、退货时，先选择供应商可以快速筛选产品'),
                _buildParagraph('• 数量支持小数：采购、销售、退货的数量都支持小数，适合按重量、体积等单位管理'),
                _buildParagraph('• 采购退货：在采购记录中输入负数数量即可记录采购退货'),
                _buildParagraph('• 日期筛选：在报表中可以使用日期范围筛选，方便查看特定时间段的数据'),
                _buildParagraph('• 数据导出：定期导出数据备份，防止数据丢失'),
                _buildParagraph('• AI 助手：使用数据分析助手可以获得专业的业务分析和建议'),
                _buildParagraph('• 字数限制：名称最多15个汉字，备注最多100个汉字，输入框右下角显示计数'),
                _buildParagraph('• 长标题查看：对账单等页面标题过长时，可左右滑动查看完整内容'),
                _buildParagraph('• 数据详情：点击任意记录或基础信息可查看完整数据和操作历史'),
              ],
            ),
            
            SizedBox(height: 24),
            
            _buildSection(
              title: '注意事项',
              icon: Icons.warning_amber,
              color: Colors.red,
              children: [
                _buildParagraph('• 数据安全：系统数据存储在本地，请定期备份，避免数据丢失'),
                _buildParagraph('• 库存管理：系统会自动检查库存，防止库存变为负数，确保数据准确性'),
                _buildParagraph('• 数据验证：所有输入都会进行验证，确保数据准确性和完整性'),
                _buildParagraph('• 多用户：不同用户的数据相互独立，登录后只能看到自己的数据'),
                _buildParagraph('• 产品关联：删除供应商前，请先修改或删除关联的产品'),
              ],
            ),
            
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSubSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8, top: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ),
        ...children,
        SizedBox(height: 8),
      ],
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          height: 1.6,
          color: Colors.grey[700],
        ),
      ),
    );
  }
}

