# בקשת גישה ל-Azure — נוסח לשליחה לאדמין

גרסה עברית של `AZURE_ACCESS_REQUEST.md`. אפשר להעתיק ולשלוח כמו שזה, אחרי השלמת השם.

---

שלום [שם],

אני מקים את התשתית ב-Azure עבור פרויקט DopaX — אפליקציית מחקר רפואי שאוספת נתוני מטופלים.
הקוד והתשתית (Bicep) כבר כתובים ונבדקו; אני חסום רק בהרשאות.

**המצב כרגע:** יש subscription והחיבור עובד. החשבון `app@dopa-x.org` מחובר ל-tenant
`5df9985a-1386-4f68-9374-2b5dd3c7a2c1` ויש לו הרשאת `Contributor` על subscription
`58613d00-0629-4629-b103-934f7245ba71` ("Azure subscription 1", Enabled). עם ההרשאה הזאת כבר
השלמתי כל מה שאפשר: ה-resource providers רשומים (סעיף 3), וה-resource group `dopax-prod-rg` קיים
ב-Israel Central.

**מה שנשאר מכם זה role assignment אחד.** הרשאת Contributor לא יכולה ליצור role assignments,
וה-deployment יוצר שלושה, ולכן בלי ההרשאה בסעיף 2 הפריסה נכשלת באמצע. סעיפים 4, 5 ו-6 הם אישורים
ולא פעולות.

> **לפני שליחה — פלטפורמת ה-compute עוד לא סגורה.** השירות Azure Container Apps לא זמין באזור
> Israel Central, ולכן ה-API, קונסולת הניהול ושתי ה-jobs לא יכולים להיפרס כפי שתוכננו. זו בעיה
> שלנו ולא של האדמין, והיא לא משנה את ההרשאות שאני מבקש כאן — אבל טבלת ה-resources תשתנה אחרי
> שנחליט. פירוט בסעיף 4 וב-`infra/README.md`. עדיין כדאי לבקש את ההרשאה בסעיף 2 עכשיו, כי היא
> נדרשת בכל מקרה, לא משנה מה ייבחר.

**מה נפרס:** resource group אחד שמכיל REST API, קונסולת ניהול פנימית, database מסוג PostgreSQL,
container ב-blob storage לנתוני המשתתפים, ושרת build קטן (Jenkins) על VM שממנו רצות הפריסות.
הכול באזור **Israel Central**, במכוון — מדובר בנתוני בריאות של מטופלים שחייבים להישאר בארץ.

להלן מה שאני צריך:

## 1. Subscription — הושלם

`58613d00-0629-4629-b103-934f7245ba71`, בשם "Azure subscription 1", במצב Enabled, ב-tenant
`dopa-x.org`. לחשבון `app@dopa-x.org` יש עליו `Contributor` והפקודה `az account show` עובדת.

הערה אחת לגבי מעקב עלויות ולגבי תיחום ה-BAA בסעיף 6: זה subscription משותף ולא נפרד. subscription
נפרד לפרויקט היה נקי יותר לשני הדברים, וכדאי לשקול את זה לפני שה-resource group מתחיל לצבור
עלויות — אבל זה לא חוסם.

## 2. הרשאות — Owner על resource group (ולא Contributor)

זו הבקשה היחידה שנשארה. ה-resource group כבר קיים, ולכן זו פקודה אחת: לתת ל-`app@dopa-x.org`
הרשאת **Owner** על `dopax-prod-rg`.

```bash
az role assignment create \
  --assignee app@dopa-x.org \
  --role Owner \
  --scope /subscriptions/58613d00-0629-4629-b103-934f7245ba71/resourceGroups/dopax-prod-rg
```

**חשוב: הרשאת Contributor לא מספיקה כאן.**

ה-deployment יוצר שלושה role assignments, כדי לחבר את ה-managed identity של האפליקציה ל-Container
Registry (AcrPull), ל-Storage Account (Storage Blob Data Contributor) ול-Key Vault (Key Vault
Secrets User). יצירת role assignment דורשת את ההרשאה
`Microsoft.Authorization/roleAssignments/write`, ו-Contributor לא כולל אותה.

התוצאה עם Contributor היא כשל באמצע התהליך — אחרי שה-database וה-storage כבר נוצרו — ולא שגיאה
מסודרת בהתחלה. לכן אני מבקש Owner מראש.

אם Owner נחשב רחב מדי מבחינת ה-policy שלכם, החלופה המקבילה והמדויקת יותר היא
**Contributor + Role Based Access Control Administrator**, שתיהן ב-scope של אותו resource group
בלבד:

```bash
SCOPE=/subscriptions/58613d00-0629-4629-b103-934f7245ba71/resourceGroups/dopax-prod-rg

az role assignment create --assignee app@dopa-x.org --role Contributor --scope "$SCOPE"
az role assignment create --assignee app@dopa-x.org \
  --role "Role Based Access Control Administrator" --scope "$SCOPE"
```

בשתי האפשרויות ההרשאה מוגבלת ל-resource group אחד. אין צורך ב-Owner ברמת ה-subscription.

## 3. רישום resource providers — הושלם

עשיתי את זה מהצד שלי. מסתבר ש-`*/register/action` כלול בהרשאת Contributor, ולכן זה לא דרש אדמין
בסוף. תשעה מתוך העשרה במצב `Registered`:

`Microsoft.App`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`, `Microsoft.Storage`,
`Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.OperationalInsights`,
`Microsoft.Insights`, `Microsoft.Compute`.

`Microsoft.Network` עדיין במצב `Registering`. הוא הגדול מבין העשרה ולוקח בדרך כלל 15–30 דקות ולא
שתיים-שלוש; לא נדרשת פעולה, אבל כדאי לאמת לפני הפריסה הראשונה:

```bash
az provider show -n Microsoft.Network --query registrationState -o tsv
```

## 4. אזור Israel Central — נבדק בפועל: חסם אחד ו-quota צפוף

**Policy: תקין.** ל-subscription אין אף policy assignment, ולכן אין כלל allowed locations שחוסם
את `israelcentral`. לא נדרשת פעולה. האזור הוא דרישה רגולטורית ולא העדפה טכנית, ולכן זה היה הסעיף
עם הפוטנציאל הגדול ביותר להפיל את הפרויקט — והוא בסדר.

**זמינות שירותים: חסם אחד.** נבדק שירות-שירות מול ה-provider manifests:

| שירות | Israel Central |
| --- | --- |
| PostgreSQL Flexible Server | זמין |
| Storage, Container Registry, Key Vault, Log Analytics | זמין |
| Virtual Machines (שרת ה-build) | זמין |
| App Service / Web App for Containers (Linux, B1–P1v3) | זמין |
| AKS, Container Instances | זמין |
| **Azure Container Apps** | **לא זמין** |

השירות Container Apps לא מוצע ב-Israel Central — לא ה-environment, לא `containerApps` ולא `jobs`.
אומת גם מול ה-provider manifest וגם ישירות מ-Microsoft ב-
[azure-container-apps#1253](https://github.com/microsoft/azure-container-apps/issues/1253), שם צוות
המוצר מציין שהאזור לא נמצא ברשימת ההתרחבות שלהם. בדיקת המצב העדכני:

```bash
az provider show --namespace Microsoft.App \
  --query "resourceTypes[?resourceType=='managedEnvironments'].locations"
```

האזורים הקרובים שכן מציעים את השירות הם UAE North, Italy North ואזורי אירופה — כולם מוציאים את
נתוני המשתתפים מהארץ, ולכן אף אחד מהם לא אפשרי. במקום זה פלטפורמת ה-compute תשתנה; פירוט
ב-`infra/README.md`.

**Quota: נקרא בהצלחה, וצפוף יותר מהצפוי.** אחרי רישום `Microsoft.Compute`:

| Quota | נוכחי | מגבלה |
| --- | --- | --- |
| Total Regional vCPUs | 0 | **4** |
| Standard BS Family vCPUs | 0 | 4 |
| Standard Bsv2 Family vCPUs | 0 | 4 |

ארבעה vCPUs באזור מספיקים לשרת ה-build מסוג Standard_B2s (שני vCPUs) ונשארים עוד שניים, כלומר
התוכנית המקורית נכנסת. זה **לא** מספיק כדי לעבור ל-AKS, שידרוש הגדלה. שימו לב שהמגבלה היא על סך
ה-vCPUs באזור, ולכן כל אפשרות שמבוססת VM מתחרה על אותם ארבעה.

```bash
az vm list-usage --location israelcentral -o table
```

בקשות להגדלת quota עוברות דרך support ticket ולוקחות יום-יומיים, ולכן אם ההחלטה על ה-compute תיפול
על משהו שמבוסס VM — כדאי לבקש את ההגדלה במקביל להרשאה בסעיף 2.

## 5. Policy — public endpoints ותגיות חובה

לא נראו policy assignments ב-scope שאני יכול לקרוא, ולכן שום דבר כאן לא חוסם כרגע. עדיין כדאי
לאשר מול ה-policy set שלכם, כי assignments שמורשים מ-management group עשויים לא להיות גלויים לי:

- **גישת רשת ציבורית.** ה-database, ה-storage account וה-Key Vault משתמשים כרגע ב-public
  endpoints המוגנים ב-firewall rules, כשה-database מוגבל לטווח הסנטינל של "Azure services only".
  אם ה-policy שלכם מחייב private endpoints — אני צריך לדעת **לפני** הבנייה. זה שינוי ארכיטקטוני
  אמיתי (compute עם VNet integration), ואני מעדיף לבנות ככה מההתחלה מאשר להסב את זה אחר כך.
- **תגיות.** נכון לעכשיו אני מגדיר `project`, `environment`, `dataClassification=phi` ו-`managedBy`.
  אם ה-policy דורש תגיות נוספות (cost center, owner וכו') — אשמח לרשימה.
- **הערה תפעולית:** ב-Key Vault מופעל purge protection, ולא ניתן לכבות אותו. זה מכוון, בגלל
  שמדובר ב-PHI, אבל המשמעות היא שה-vault נשמר 90 יום גם לאחר מחיקה. כדאי לדעת לפני שמנסים למחוק
  ולבנות מחדש מיד.

## 6. HIPAA BAA

מדובר בנתוני בריאות של מטופלים, והאזור Israel Central נבחר כדי שהמידע יישאר בארץ.
בבקשה לאשר שה-BAA של Microsoft מכסה את subscription `58613d00-0629-4629-b103-934f7245ba71`,
ולעדכן אם תהליך ה-compliance דורש ממני משהו נוסף.

זו הנקודה היחידה שבה ה-subscription המשותף שהוזכר בסעיף 1 באמת משנה. אם ה-BAA מתוחם לפי
subscription, קל יותר להצהיר על subscription נפרד ל-DopaX מאשר על אחד משותף שנושא גם workloads
אחרים.

## 7. תקציב

- **כ-60$ לחודש** לפלטפורמה עצמה: database, שתי האפליקציות, registry, logs ו-Key Vault.
- **כ-85$ לחודש בסך הכל** בסביבות חודש 12, כולל ארכיון ההעלאות.
- **כ-45$ לחודש נוספים** לשרת ה-build: VM מסוג Standard_B2s (35.04$), disk של 64GB Standard SSD
  (6.38$ כולל דמי mount) ו-static public IP (3.65$). שלושת המחירים האלה נבדקו מול ה-API הציבורי
  של מחירי Azure עבור Israel Central, ולא הוערכו.
- **אחסון הוא החלק היחיד שגדל ללא הגבלה**, כי נתוני המחקר נשמרים לצמיתות. ההערכה מבוססת על
  כ-0.4GB למשתתף ליום עבור ימים שבהם יש העלאה, ובהיענות של כ-60% — כלומר כ-**300GB לחודש**
  ב-43 משתתפים.

**חשוב לציין שזו הערכה ולא מדידה.** התיקייה ההיסטורית ב-Google Drive מעולם לא נסרקה, והמספר
שמופיע בתוכנית המיגרציה שלנו (1–2GB) הוא תקרה שנמדדה בימים העמוסים ביותר, לא ממוצע. אם בפועל
הממוצע יתברר כתקרה, המספר בחודש 12 מתקרב ל-156$ לחודש. אנחנו מודדים את זה לפני שזה משפיע על
התקציב.

הערה על עלויות: באזור Israel Central אין tier מסוג Archive, ולכן Cold LRS במחיר
0.0045$ ל-GB לחודש הוא הרצפה הזולה ביותר. ב-Sweden Central מחיר Archive הוא 0.00099$ והיה חוסך
כ-40% משורת האחסון — אבל זה היה מוציא את נתוני המטופלים מהארץ, ולכן זו לא אופציה.

אשמח אם תגדירו **budget alert** על ה-resource group. הפירוט המלא, כולל השוואה בין אזורים
ותחזית עד 20,000 משתתפים, נמצא ב-`infra/DopaX-Azure-cost-model.pdf`.

## 8. CI/CD — כבר מכוסה למעלה, לא נדרשת הרשאה נוספת

הפריסות רצות מ-Jenkins על ה-VM שמופיע למעלה, ולא משירות CI מנוהל. שתי נקודות שכדאי להכיר:

- **בלי app registration ובלי סוד שמור באף מקום.** ל-VM יוקצה system-assigned managed identity,
  וה-pipeline מתחבר באמצעות `az login --identity`. אין client secret ואין federated credential
  שצריך ליצור, לסבב, או שעלול להיחשף.
- **לא נדרשת ממך פעולה מעבר לסעיף 2.** ה-identity הזה צריך `AcrPush` על ה-registry,
  `Key Vault Secrets User` על ה-vault ו-`Contributor` על ה-resource group. שלושתם ב-scope של
  `dopax-prod-rg`, ולכן הרשאת ה-Owner מסעיף 2 מספיקה כדי שאני אגדיר אותם בעצמי.

מה שזה מוסיף לצד שלך זה רק ה-quota ל-B-series בסעיף 4, והמגבלה הנוכחית של ארבעה vCPUs באזור כבר
מכסה אותו. `Microsoft.Compute` רשום.

---

## איך נדע שהגישה תקינה

אחרי ההרשאה בסעיף 2, זה מוכיח שצד ההרשאות הושלם:

```bash
az login
az account set --subscription 58613d00-0629-4629-b103-934f7245ba71

az role assignment list --assignee app@dopa-x.org \
  --scope /subscriptions/58613d00-0629-4629-b103-934f7245ba71/resourceGroups/dopax-prod-rg \
  -o table
```

הבדיקה המלאה יותר היא `./infra/deploy.sh --what-if`, שלא כותב כלום ורק מציג אילו resources ייווצרו
— אבל היא לא תעבור עד שנפתור את בעיית Container Apps מסעיף 4, כי ה-template מכוון ל-resource type
שלא קיים באזור הזה.

---

## סיכום מצב

| סעיף | מצב |
| --- | --- |
| 1. Subscription | הושלם — `58613d00-0629-4629-b103-934f7245ba71` |
| 2. הרשאות | **ממתין לאדמין** |
| 3. Resource providers | הושלם — 9 מתוך 10 רשומים, `Microsoft.Network` עוד בתהליך |
| 4. Policy לאזור | הושלם — אין assignment שחוסם את `israelcentral` |
| 4. Quota לאזור | הושלם — 4 vCPUs, מספיק לתוכנית הנוכחית |
| 4. Container Apps באזור | **חסום — לא זמין, בתכנון מחדש אצלנו** |
| 5. Policy exemptions | לאשר policy שמורש מ-management group |
| 6. HIPAA BAA | לאשר כיסוי ל-subscription הזה |

תודה רבה,
[השם שלך]
