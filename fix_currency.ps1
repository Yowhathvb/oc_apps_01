 = @(
  "c:\zharfan\project\our-chat\apps\oc_apps_01\lib\screens\cart_screen.dart",
  "c:\zharfan\project\our-chat\apps\oc_apps_01\lib\screens\checkout_screen.dart",
  "c:\zharfan\project\our-chat\apps\oc_apps_01\lib\screens\marketplace_home_screen.dart",
  "c:\zharfan\project\our-chat\apps\oc_apps_01\lib\screens\product_detail_screen.dart",
  "c:\zharfan\project\our-chat\apps\oc_apps_01\lib\screens\store_dashboard_screen.dart"
)
foreach ( in ) {
   = Get-Content  -Raw
   =  -replace "import '../models/product_model.dart';", "import '../models/product_model.dart';
import '../utils/format_utils.dart';"
  
  # Replace 'Rp ' with FormatUtils.formatRupiah(expression)
   = [regex]::Replace(, "'Rp \\'", "FormatUtils.formatRupiah($1)")
  
  # Replace 'Rp '
   = [regex]::Replace(, "'Rp \\'", "FormatUtils.formatRupiah($1)")
  
  # For the edge case '... x Rp ' we might need to handle it separately
   = [regex]::Replace(, "Rp \\", "\")
  
  Set-Content  -Value 
}
