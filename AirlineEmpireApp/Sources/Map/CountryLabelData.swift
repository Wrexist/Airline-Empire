import Foundation

/// Country labels, from Natural Earth's ``ne_110m_admin_0_countries`` — public
/// domain, the same source as the coastlines (docs/MAP_REALISM_RESEARCH.md).
///
/// Four fields per country: name, ISO 3166-1 alpha-2, and the anchor Natural
/// Earth's own cartographers chose for the label (`LABEL_X`, `LABEL_Y`) —
/// which is not the centroid, and is why "Norway" lands on Norway rather than
/// in the sea off a fjord-shaped average.
///
/// The fifth is `MIN_LABEL`: the scale at or beyond which Natural Earth
/// recommends drawing this label at all. Using it means the question "which
/// countries belong on a world view" is answered by cartographers rather than
/// by a rule invented here — Russia, Brazil and India at the widest, Andorra
/// only when you are looking at the Pyrenees.
///
/// The two entries Natural Earth marks `-99` (Northern Cyprus, Somaliland)
/// are dropped. They have no ISO code, so no flag; and a game has no business
/// taking a position on them.
///
/// A string literal for the same reason as `WorldGeometryData`: 875 array
/// literal elements is a Swift type-checker problem, and a string is not.
enum CountryLabelData {
    static let all = """
Australia|AU|134.05|-24.13|1.7
Brazil|BR|-49.56|-12.1|1.7
Canada|CA|-101.91|60.32|1.7
Chile|CL|-72.32|-38.15|1.7
China|CN|106.34|32.5|1.7
Egypt|EG|29.45|26.19|1.7
France|FR|2.55|46.7|1.7
Germany|DE|9.68|50.96|1.7
Greenland|GL|-39.34|74.32|1.7
India|IN|79.36|22.69|1.7
Indonesia|ID|101.89|-0.95|1.7
Japan|JP|138.44|36.14|1.7
Kenya|KE|37.91|0.55|1.7
Nigeria|NG|7.5|9.44|1.7
Russia|RU|44.69|58.25|1.7
Saudi Arabia|SA|44.7|23.81|1.7
South Africa|ZA|23.67|-29.71|1.7
United Kingdom|GB|-2.12|54.4|1.7
United States of America|US|-97.48|39.54|1.7
Argentina|AR|-64.17|-33.5|2.0
Dem. Rep. Congo|CD|23.46|-1.86|2.0
Ethiopia|ET|39.09|8.03|2.0
Iceland|IS|-18.67|64.78|2.0
Italy|IT|11.08|44.73|2.0
Mexico|MX|-102.29|23.92|2.0
New Zealand|NZ|172.79|-39.76|2.0
Peru|PE|-72.9|-12.98|2.0
Spain|ES|-3.46|40.09|2.0
Sweden|SE|19.02|65.86|2.0
Turkey|TR|34.51|39.35|2.0
Vietnam|VN|105.39|21.72|2.0
Algeria|DZ|2.81|27.4|2.5
Costa Rica|CR|-84.08|10.07|2.5
Côte d'Ivoire|CI|-5.57|7.49|2.5
Iran|IR|54.93|32.17|2.5
Papua New Guinea|PG|143.91|-5.7|2.5
Philippines|PH|122.47|11.2|2.5
Poland|PL|19.49|51.99|2.5
South Korea|KR|128.13|36.38|2.5
Sudan|SD|29.26|16.33|2.5
Venezuela|VE|-64.6|7.18|2.5
Zimbabwe|ZW|29.93|-18.91|2.5
Cuba|CU|-77.98|21.33|2.7
Ghana|GH|-1.04|7.72|2.7
Greece|GR|21.73|39.49|2.7
Kazakhstan|KZ|68.69|49.05|2.7
Madagascar|MG|46.7|-18.63|2.7
Morocco|MA|-7.19|31.65|2.7
Pakistan|PK|68.55|29.33|2.7
Senegal|SN|-14.78|15.14|2.7
Thailand|TH|101.07|15.46|2.7
Ukraine|UA|32.14|49.72|2.7
Afghanistan|AF|66.5|34.16|3.0
Angola|AO|17.98|-12.18|3.0
Austria|AT|14.13|47.52|3.0
Bangladesh|BD|89.68|24.21|3.0
Belarus|BY|28.42|53.82|3.0
Bolivia|BO|-64.59|-16.67|3.0
Burkina Faso|BF|-1.36|12.67|3.0
Cambodia|KH|104.5|12.65|3.0
Cameroon|CM|12.47|4.59|3.0
Chad|TD|18.65|15.14|3.0
Colombia|CO|-73.17|3.37|3.0
Denmark|DK|9.02|55.97|3.0
Ecuador|EC|-78.19|-1.26|3.0
Estonia|EE|25.87|58.72|3.0
Fiji|FJ|177.98|-17.83|3.0
Finland|FI|27.28|63.25|3.0
Gabon|GA|11.84|-0.44|3.0
Guatemala|GT|-90.5|14.98|3.0
Guinea|GN|-10.02|10.62|3.0
Iraq|IQ|43.26|33.09|3.0
Ireland|IE|-7.8|53.08|3.0
Israel|IL|34.85|30.91|3.0
Kyrgyzstan|KG|74.53|41.67|3.0
Libya|LY|18.01|26.64|3.0
Malaysia|MY|113.84|2.53|3.0
Mali|ML|-2.04|18.69|3.0
Mauritania|MR|-9.74|19.59|3.0
Mongolia|MN|104.15|46.0|3.0
Mozambique|MZ|37.84|-13.94|3.0
Myanmar|MM|95.8|21.57|3.0
Namibia|NA|17.11|-20.58|3.0
Nepal|NP|83.64|28.3|3.0
Niger|NE|9.5|17.45|3.0
North Korea|KP|126.44|39.89|3.0
Norway|NO|9.68|61.36|3.0
Paraguay|PY|-60.15|-21.67|3.0
Portugal|PT|-8.27|39.61|3.0
Puerto Rico|PR|-66.48|18.23|3.0
Romania|RO|24.97|45.73|3.0
Rwanda|RW|30.1|-1.9|3.0
S. Sudan|SS|30.39|7.23|3.0
Solomon Is.|SB|159.17|-8.03|3.0
Sri Lanka|LK|80.7|7.58|3.0
Syria|SY|38.28|35.01|3.0
Tanzania|TZ|34.96|-6.05|3.0
Tunisia|TN|9.01|33.69|3.0
Turkmenistan|TM|58.68|39.86|3.0
Uganda|UG|32.95|1.97|3.0
Uruguay|UY|-55.97|-32.96|3.0
Uzbekistan|UZ|64.01|41.69|3.0
Yemen|YE|45.87|15.33|3.0
Zambia|ZM|26.4|-14.66|3.0
Antarctica|AQ|35.89|-79.84|4.0
Azerbaijan|AZ|47.21|40.4|4.0
Bahamas|BS|-77.15|26.4|4.0
Belgium|BE|4.8|50.79|4.0
Benin|BJ|2.35|10.32|4.0
Bhutan|BT|90.04|27.54|4.0
Botswana|BW|24.18|-22.1|4.0
Brunei|BN|114.55|4.45|4.0
Bulgaria|BG|25.16|42.51|4.0
Burundi|BI|29.92|-3.33|4.0
Central African Rep.|CF|20.91|6.99|4.0
Congo|CG|15.9|0.14|4.0
Croatia|HR|16.37|45.81|4.0
Czechia|CZ|15.38|49.88|4.0
Djibouti|DJ|42.5|11.98|4.0
Eq. Guinea|GQ|8.99|2.33|4.0
Eritrea|ER|38.29|15.79|4.0
Fr. S. Antarctic Lands|TF|69.12|-49.3|4.0
Georgia|GE|43.74|41.87|4.0
Guyana|GY|-58.94|5.12|4.0
Haiti|HT|-72.22|19.26|4.0
Hungary|HU|19.45|47.09|4.0
Jamaica|JM|-77.32|18.14|4.0
Jordan|JO|36.38|30.81|4.0
Laos|LA|102.53|19.43|4.0
Latvia|LV|25.46|57.07|4.0
Lebanon|LB|35.99|34.13|4.0
Lesotho|LS|28.25|-29.48|4.0
Liberia|LR|-9.46|6.45|4.0
Lithuania|LT|24.09|55.1|4.0
Malawi|MW|33.61|-13.39|4.0
Netherlands|NL|5.61|52.42|4.0
Nicaragua|NI|-85.07|12.67|4.0
Oman|OM|57.34|22.12|4.0
Panama|PA|-80.35|8.72|4.0
Qatar|QA|51.14|25.24|4.0
Serbia|RS|20.79|44.19|4.0
Sierra Leone|SL|-11.76|8.62|4.0
Slovakia|SK|19.05|48.73|4.0
Somalia|SO|45.19|3.57|4.0
Suriname|SR|-55.91|4.14|4.0
Switzerland|CH|7.46|46.72|4.0
Tajikistan|TJ|72.59|38.2|4.0
Timor-Leste|TL|125.85|-8.8|4.0
United Arab Emirates|AE|54.55|23.47|4.0
Vanuatu|VU|166.91|-15.37|4.0
eSwatini|SZ|31.47|-26.53|4.0
Bosnia and Herz.|BA|18.07|44.09|4.5
Cyprus|CY|33.08|34.91|4.5
Dominican Rep.|DO|-70.65|19.1|4.5
Falkland Is.|FK|-58.74|-51.61|4.5
Honduras|HN|-86.89|14.79|4.5
Palestine|PS|35.29|32.05|4.5
Taiwan|TW|120.87|23.65|4.5
Trinidad and Tobago|TT|-60.92|11.0|4.5
New Caledonia|NC|165.08|-21.06|4.6
Albania|AL|20.11|40.65|5.0
Armenia|AM|44.8|40.46|5.0
Belize|BZ|-88.71|17.2|5.0
El Salvador|SV|-88.89|13.69|5.0
Gambia|GM|-15.0|13.64|5.0
Guinea-Bissau|GW|-14.52|12.16|5.0
Kosovo|XK|20.86|42.59|5.0
Kuwait|KW|47.31|29.41|5.0
Moldova|MD|28.49|47.43|5.0
Montenegro|ME|19.14|42.8|5.0
North Macedonia|MK|21.56|41.56|5.0
Slovenia|SI|14.92|46.06|5.0
Togo|TG|1.06|8.81|5.0
Luxembourg|LU|6.08|49.73|5.7
W. Sahara|EH|-12.63|23.97|6.0
"""
}
