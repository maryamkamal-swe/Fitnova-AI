extension TitleCaseExtension on String {
  String toTitleCase() => replaceAll('_', ' ')
      .split(' ')
      .map((word) => word.isEmpty
          ? ''
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');

  String toNameCase() => trim().toTitleCase();
}
