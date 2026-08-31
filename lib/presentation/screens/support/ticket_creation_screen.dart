import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/common/buttons.dart';
import '../../widgets/common/inputs.dart';

/// Ticket Creation Screen - Complaints/Support submission
class TicketCreationScreen extends ConsumerStatefulWidget {
  final String? preselectedCategory;
  const TicketCreationScreen({Key? key, this.preselectedCategory}) : super(key: key);

  @override
  ConsumerState<TicketCreationScreen> createState() => _TicketCreationScreenState();
}

class _TicketCreationScreenState extends ConsumerState<TicketCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  String _selectedCategory = '';
  String _priority = 'medium';
  bool _isSubmitting = false;
  String? _errorMessage;

  // Enhanced categories with descriptions
  final List<Map<String, String>> _categories = [
    {'value': 'loan_issue', 'title': 'Loan Issue', 'desc': 'Problems with loan applications, repayments, or interest'},
    {'value': 'guarantor_consent', 'title': 'Guarantor Request', 'desc': 'Issues with guarantor consent or requests'},
    {'value': 'account_kyc', 'title': 'Account / KYC', 'desc': 'Profile updates, identity verification, documents'},
    {'value': 'contribution', 'title': 'Contribution Problem', 'desc': 'Issues with savings or contributions'},
    {'value': 'withdrawal', 'title': 'Withdrawal Issue', 'desc': 'Problems with fund withdrawals or delays'},
    {'value': 'technical_bug', 'title': 'App Bug / Error', 'desc': 'Technical issues or bugs in the app'},
    {'value': 'complaint', 'title': 'General Complaint', 'desc': 'Other complaints or concerns'},
    {'value': 'other', 'title': 'Other', 'desc': 'Anything else'},
  ];

  // Priority options
  final List<Map<String, dynamic>> _priorities = [
    {'value': 'low', 'label': 'Low', 'desc': 'Not urgent, can wait'},
    {'value': 'medium', 'label': 'Medium', 'desc': 'Normal priority'},
    {'value': 'high', 'label': 'High', 'desc': 'Needs quick attention'},
    {'value': 'urgent', 'label': 'Urgent', 'desc': 'Critical issue, needs immediate action'},
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    if (widget.preselectedCategory != null) _selectedCategory = widget.preselectedCategory!;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory.isEmpty) { 
      setState(() => _errorMessage = 'Please select a category'); 
      return; 
    }
    
    setState(() { _isSubmitting = true; _errorMessage = null; });
    
    try {
      final response = await ApiClient().getDio().post('/tickets', data: {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'priority': _priority,
      });
      
      if (response.data['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your complaint has been submitted successfully!'),
            backgroundColor: CoopvestColors.success,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/tickets');
      } else {
        setState(() => _errorMessage = response.data['error'] ?? 'Failed to submit complaint');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to submit complaint. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.iconPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Submit Complaint', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: CoopvestColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: CoopvestColors.info.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: CoopvestColors.info),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'We take all complaints seriously and aim to resolve them within 24-48 hours.',
                          style: TextStyle(color: context.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(color: CoopvestColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [const Icon(Icons.error_outline, color: CoopvestColors.error), const SizedBox(width: 12), Expanded(child: Text(_errorMessage!, style: const TextStyle(color: CoopvestColors.error)))]),
                  ),
                
                const SizedBox(height: 24),
                
                // Category selection
                Text('What is this about? *', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                const SizedBox(height: 12),
                ..._categories.map((category) {
                  final isSelected = _selectedCategory == category['value'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setState(() { _selectedCategory = category['value']!; _errorMessage = null; }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected ? CoopvestColors.primary.withOpacity(0.1) : context.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? CoopvestColors.primary : context.dividerColor,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? CoopvestColors.primary : Colors.transparent,
                                border: Border.all(color: isSelected ? CoopvestColors.primary : context.textSecondary),
                              ),
                              child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(category['title']!, style: TextStyle(fontWeight: FontWeight.w600, color: context.textPrimary)),
                                  Text(category['desc']!, style: TextStyle(fontSize: 12, color: context.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                
                const SizedBox(height: 24),
                
                // Priority selection
                Text('How urgent is this? *', style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _priorities.map((priority) {
                    final isSelected = _priority == priority['value'];
                    return ChoiceChip(
                      label: Text(priority['label'] as String),
                      selected: isSelected,
                      onSelected: (selected) => setState(() { _priority = priority['value'] as String; }),
                      selectedColor: _getPriorityColor(priority['value'] as String),
                      labelStyle: TextStyle(color: isSelected ? Colors.white : context.textPrimary, fontWeight: FontWeight.w500),
                    );
                  }).toList(),
                ),
                
                const SizedBox(height: 24),
                
                AppTextField(
                  label: 'Subject *', 
                  hint: 'Brief summary of the issue', 
                  controller: _titleController, 
                  validator: (v) => v == null || v.isEmpty ? 'Please enter a subject' : (v.length < 5 ? 'Subject must be at least 5 characters' : null)
                ),
                const SizedBox(height: 20),
                
                AppTextField(
                  label: 'Description *', 
                  hint: 'Provide as much detail as possible about your issue...', 
                  controller: _descriptionController, 
                  maxLines: 6, 
                  validator: (v) => v == null || v.isEmpty ? 'Please describe your issue' : (v.length < 20 ? 'Please provide more details (at least 20 characters)' : null)
                ),
                
                const SizedBox(height: 32),
                
                PrimaryButton(
                  label: 'Submit Complaint', 
                  onPressed: _submitTicket, 
                  isLoading: _isSubmitting, 
                  width: double.infinity,
                  icon: const Icon(Icons.send, color: Colors.white),
                ),
                
                const SizedBox(height: 16),
                
                Center(
                  child: Text(
                    'You will receive a confirmation and our team will respond within 24-48 hours.',
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'low': return Colors.grey;
      case 'medium': return CoopvestColors.info;
      case 'high': return CoopvestColors.warning;
      case 'urgent': return CoopvestColors.error;
      default: return CoopvestColors.primary;
    }
  }
}
