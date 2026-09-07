String formatSupervisorLine(String phone) {
  final trimmed = phone.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.toLowerCase().startsWith('supervisor')) return trimmed;
  return 'Supervisor : $trimmed';
}
