
de.Ordinal		= "." -- e.g. "9."
pl.Ordinal 		= "."
da.Ordinal 		= "."
et.Ordinal 		= "."
lv.Ordinal 		= "."
no.Ordinal 		= "."
tr.Ordinal 		= "."
sl.Ordinal 		= "."
sk.Ordinal 		= "."
hu.Ordinal 		= "."
cs.Ordinal 		= "."
sr.Ordinal 		= "."
hr.Ordinal 		= "."

pt.Ordinal 		= "." -- TODO: handle gender suffix indicators ºª
es.Ordinal 		= "." -- TODO: handle gender suffix indicators ºª

function vocabulary.en.Ordinal(number)
	number = tonumber(number)
	if number ==11 or number==12 or number==13 then
		return "th"
	else
		number = tonumber(string.sub(number,-1))
		if number==1 then return "st"
		elseif number==2 then return "nd"
		elseif number==3 then return "rd"
		else return "th" end
	end
end
function vocabulary.en.OrdinalHTML(number)
	number = tonumber(number)
	if number ==11 or number==12 or number==13 then
		return "<sup>th</sup>"
	else
		number = tonumber(string.sub(number,-1))
		if number==1 then return "<sup>st</sup>"
		elseif number==2 then return "<sup>nd</sup>"
		elseif number==3 then return "<sup>rd</sup>"
		else return "<sup>th</sup>" end
	end
end
vocabulary.en.OrdinalDay = vocabulary.en.Ordinal
vocabulary.en.OrdinalDayHTML = vocabulary.en.OrdinalHTML

function vocabulary.fr.Ordinal(number) -- doesn't support gender or plurals
	if tonumber(number) ==1 then
		return "er" -- masculine form but correct for numbers without context
	else
		return "ème"
	end
end
function vocabulary.fr.OrdinalHTML(number) -- doesn't support gender or plurals
	if tonumber(number) ==1 then
		return "<sup>er</sup>" -- masculine form but correct for numbers without context
	else
		return "<sup>ème</sup>"
	end
end
function vocabulary.fr.OrdinalDay(number) if tonumber(number) ==1 then return "er" end end
function vocabulary.fr.OrdinalDayHTML(number) if tonumber(number) ==1 then return "<sup>er</sup>" end end

function vocabulary.de.OrdinalDay(number) return "." end
vocabulary.de.OrdinalDayHTML = vocabulary.de.OrdinalDay

--[[vocabulary.id.OrdinalPre			= -- TODO: handle prefixes
function(number)
	number = tonumber(number)
	if number ==1 then
		return "pertama"
	else
		return "ke-"
	end
end--]]
--ms.OrdinalPre			= id.OrdinalPre

en.numbers	={"one","two","three","four","five","six","seven","eight","nine","ten"}
fr.numbers	={"un","deux","trois","quatre","cinq","six","sept","huit","neuf","dix"}
en.WWW		={"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
fr.WWW		={"dimanche", "lundi", "mardi", "mecredi", "jeudi", "vendredi", "samedi"}
de.WWW		={"Sonntag","Montag","Dienstag","Mittwoch","Donnerstag","Freitag","Samstag"}
en.WW			={"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
fr.WW			={"dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."}
de.WW			={"So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"}
en.W			={"Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"}
de.W			={"So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"}
fr.W			={"di", "lu", "ma", "me", "je", "ve", "sa"}
en.MMM		={"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
fr.MMM		={"janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"}
de.MMM		={"Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"}
en.MM			={"Jan.", "Feb.", "March", "April", "May", "June", "July", "Aug.", "Sept.", "Oct.", "Nov.", "Dec."}
de.MM			={"Jan.", "Feb.", "März", "April", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."}
fr.MM			={"jan.", "févr.", "mars", "avril", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."}
en.M			={"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
de.M			={"Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sept", "Okt", "Nov", "Dez."}
fr.M			={"janv", "fév", "mars", "avr", "mai", "juin", "juil", "août", "sep", "oct", "nov", "déc"}
fr.decimal	=","
en.decimal	="."
de.decimal	=","

en['']				="⚑unspecified"
fr['']				="⚑indéterminé"
de['']				="⚑nicht spezifiziert"

en.goodmorn				="Good morning"
it.goodmorn				="Buongiorno"
en.goodday				="Good day"
it.goodday				="Buona giornata"
en.goodnoon				="Good afternoon"
it.goodnoon				="Buon pomeriggio"
en.goodeve				="Good evening"
it.goodeve				="Buonasera"

local greetings ={"Hello","Hiya","Hullo","Howdy","Hi","What’s up","G’day","Greetings","Ahoy","Allrighty","Aloha","How's business"} -- used in many places including emails to guest customers thus can't include "welcome" or overly familiar -- TODO: use a different array for guest emails


-- languages
en.language_en	="English"
['en-gb']['language_en-gb']	="British English"
['en-au']['language_en-au']	="Australian English"
['en-ca']['language_en-ca']	="Canadian English"
['en-us']['language_en-us']	="U.S. English"

pt.language_pt	="Português"
['pt-br']['language_pt-br']	="Português Brasil"
es.language_es	="Español"
fr.language_fr	="Français"
['fr-ca']['language_fr-ca']	="Français Canadien"
['fr-be']['language_fr-be']	="Français Belgique"
de.language_de	="Deutsch"
['de-at']['language_de-at']	="Deutsch Österreichische"
it.language_lt	="Lietuvių"
it.language_it	="Italiano"
ar.language_ar	="العربية"
zh.language_zh	="汉语"
cz.language_cz	="Český"
dk.language_dk	="Danske"
nl.language_nl	="Nederlands"
fi.language_fi	="Suomalainen"
ja.language_ja	="日本"
no.language_no	="Norske"
pl.language_pl	="Polski"
ru.language_ru	="Pусский"
sv.language_sv	="Svenska"
ga.language_ga	="Gaeilge"
da.language_da	="Danske"
af.language_af	="Afrikaanse"
id.language_id	="Indonesian"
ko.language_ko	="한국의"
hi.language_hi	="हिन्दी"
vi.language_vi	="Việt"
ru.language_ru	="русский"
uk.language_uk	="украї́нська"
el.language_el	="Ελληνικά"
tr.language_tr	="Türkçe"
hr.language_hr	="Hrvatski"
hr.language_ar	="Afrikaans"
hr.language_hu	="magyar nyelv"

-- countries
-- country name must be specified in its default language
-- typically one would use country_familiar_.. or country_..
en.country_tw		="Taiwan"
zh.country_tw		="中華民國"
en.country_sg		="Singapore"
zh.country_sg		="新加坡"
en.country_pt		="Portugal"
pt.country_pt		="Portugal"
en.country_ae		="United Arab Emirates"
en.country_abbr_ae		="the UAE"
ar.country_ae		="الامارات العربية المتحدة"
en.country_ie		="Ireland"
ga.country_ie		="Éire"
fr.country_familiar_ie	="Irlande"
fr.country_ie		="l'Irlande"
en.country_fi		="Finland"
fi.country_fi		="Suomi"
en.country_dk		="Denmark"
da.country_dk		="Danmark"
en.country_at		="Austria"
de.country_at		="Österreich"
['de-at'].country_at		="Österreich"
en.country_no		="Norway"
no.country_no		="Norge"
en.country_za		="South Africa"
af.country_za		="Suid-Afrika"
en.country_sa		="Saudi Arabia"
ar.country_sa		="العربية السعودية"
en.country_se		="Sweden"
sv.country_se		="Sverige"
en.country_ch		="Switzerland"
fr.country_ch		="Suisse"
fr.country_familiar_ch		="la Suisse"
it.country_ch		="Svizzera"
de.country_ch		="Schweiz"
en.country_li		="Liechtenstein"
fr.country_li		="Liechtenstein"
de.country_li		="Liechtenstein"
en.country_be		="Belgium"
nl.country_be		="België"
fr.country_be		="Belgique"
['fr-be'].country_be		="Belgique"
de.country_be		="Belgien"
fr.country_familiar_be		="la Belgique"
en.country_id		="Indonesia"
id.country_id		="Indonesia"
en.country_pl		="Poland"
pl.country_pl		="Polska"
en.country_nl		="The Netherlands"
nl.country_nl		="Nederland"
en.country_kr		="South Korea"
ko.country_kr		="대한민국"
en.country_mx		="Mexico"
es.country_mx		="México"
en.country_ni		="Nicaragua"
es.country_ni		="Nicaragua"
en.country_my		="Malaysia"
en.country_in		="India"
hi.country_in		="भारत"
en.country_br		="Brazil"
pt.country_br		="Brasil"
en.country_bz		="Belize"
['pt-br'].country_br		="Brasil"
en.country_nz		="New Zealand"
['en-au'].country_nz		="New Zealand"
en.country_au		="Australia"
['en-au'].country_au		="Australia"
en.country_es		="Spain"
es.country_es		="España"
fr.country_es			="Espagne"
fr.country_familiar_es	="l'Espagne"
en.country_ru		="Russia"
ru.country_ru		="Россия"
fr.country_familiar_ru				="la Russie"
en.country_it		="Italy"
it.country_it		="Italia"
fr.country_it		="Italie"
fr.country_familiar_it		="l'Italie"
en.country_fr		="France"
fr.country_fr		="France"
en.country_familiar_fr				="France"
fr.country_familiar_fr				="la France"
en.country_de		="Germany"
de.country_de		="Deutschland"
fr.country_familiar_de				="l'Allemagne"
fr.country_de		="Allemagne"
en.country_cn		="China"
zh.country_cn		="中国"
en.country_vn		="Vietnam"
vi.country_vn		="Việt Nam"
en.country_jp		="Japan"
ja.country_jp		="日本"
en.country_ca		="Canada"
fr.country_ca		="Canada"
['en-ca'].country_ca		="Canada"
['fr-ca'].country_ca		="Canada"
en.country_gb		="United Kingdom"
['en-gb'].country_gb		="United Kingdom"
en.country_familiar_gb				="the UK"
fr.country_familiar_gb				="la Royaume Uni"
en.country_familiar_us		="the USA"
en.country_abbr_us		="USA"
en.country_us		="United States"
['en-us'].country_us		="United States"
es.country_us		="Estados Unidos"
fr.country_familiar_us				="les États-Unis"
en.country_eu		="Europe"
de.country_eu		="Europa"
en.country_familiar_eu				="Europe"
fr.country_familiar_eu				="l'Europe"
fr.country_eu		="Europe"
es.country_eu		="Europa"
en.country_eg		="Egypt"
ar.country_eg		="مصر" -- shortform
en.country_ge		="Georgia"
ka.country_ge		="საქართველო"
lt.country_lt		="Lietuvos"
en.country_lt		="Lithuania"
en.country_am		="Armenia"
hy.country_am		="Հայաստանի"
en.country_gr		="Greece"
el.country_gr		="Ελληνική"
en.country_bg		="Bulgaria"
bg.country_bg		="България"
en.country_ma		="Morocco"
ar.country_ma		="المملكة المغربية" -- moroccan kingdom
fr.country_ma		="Maroc"
en.country_co		="Colombia"
es.country_co		="Colombia"
en.country_rs		="Serbia"
sr.country_rs		="Srbija"
en.country_me		="Montenegro"
cnr.country_me		="Црна Гора"
en.country_ro		="Romania"
ro.country_ro		="România"
en.country_ee		="Estonia"
et.country_ee		="Eesti Vabariik"
en.country_th		="Thailand"
th.country_th		="ราชอาณาจักรไทย"
en.country_kh		="Cambodia"
km.country_kh		="ព្រះរាជាណាចក្រកម្ពុជា"
en.country_ec		="Ecuador"
es.country_ec		="Ecuador"
en.country_tz		="Tanzania"
en.country_ci		="Ivory Coast"
fr.country_ci		="Côte d'Ivoire"
es.country_ph		="Pilipinas"
en.country_ph		="Philippines"
en.country_cr		="Costa Rica"
es.country_cr		="Costa Rica"
en.country_mt		="Malta"
mt.country_mt		="Malta"
en.country_lk		="Sri Lanka"
si.country_lk		="ශ්‍රී ලංකා"
ta.country_lk		="இலங்கை"
ru.country_ru		="Россия"
en.country_ru		="Russia"
uk.country_ua		="Україна"
en.country_ua		="Ukraine"
zh.country_hk		="香港"
en.country_hk		="Hong Kong"
el.country_cy		="Κύπρος"
tr.country_cy		="Kıbrıs"
en.country_cy		="Cyprus"
en.country_ve		="Venezuela"
es.country_ve		="Venezuela"
en.country_ar		="Argentina"
es.country_ar		="Argentina"
en.country_ph		="Philippines"
es.country_ph		="Pilipinas"
en.country_uy		="Uruguay"
es.country_uy		="Uruguay"
ar.country_tn		="تونس"
en.country_tn		="Tunisia"
fr.country_tn		="Tunisie"
es.country_pa		="Panamá"
en.country_pa		="Panama"
en.country_hr		="Croatia"
hr.country_hr		="Hrvatska"
en.country_na		="Namibia"
en.country_hu		="Hungary"
hu.country_hu		="Magyarország"

-- template
en.poweredby			="powered by"
fr.poweredby			="propulsé par"
de.poweredby			="unterstützt von"
-- account and signin
en.greetings = {"Hello","Hiya","Hola","Hullo","Howdy","Hi","Heya",[[What’s up]],[[G’day]],"Greetings","Ahoy","Allrighty","Welcome","Aloha","Yoo-hoo"}
fr.greetings = {"Salut","Allô","Bonjour","Bienvenue","Coucou","Hola","Hello"}
en.myfriends = {"friend","my friend","chum","buddy"}
fr.myfriends = {"mon pote","buddy","mon ami"}
en.greeting			="hello"
fr.greeting			="salut"
de.greeting			="hallo"
en.thanks				="thanks"
fr.thanks				="merci"
de.thanks				="Danke"
en.your				="your"
fr.your				="votre"
de.your				="ihr"
en.account			="account"
fr.account			="compte"
de.account			="Konto"
en.youraccount		="your Account"
fr.youraccount		="votre Compte"
de.youraccount		="ihr Konto"
en.actionsignin		="sign me in"
fr.actionsignin		="se connecter"
de.actionsignin		="Schreib mich ein"
en.signout			="signout"
fr.signout			="quitter"
de.signout			="Ausloggen"
en.signin				="sign-in"
fr.signin				="se connecter"
de.signin				="Einloggen"
en.signinurn			="signin"
fr.signinurn			="connexion"
en.pleaseselect			="Please select…"
fr.pleaseselect			="Veuillez choisir…"
en.signin_h1			="Please sign-in"
fr.signin_h1			="Veuillez vous connecter"
de.signin_h1			="Bitte einloggen"
en.identifier			="identification"
fr.identifier			="identification"
de.identifier			="Identifikation"
en.password			="password"
fr.password			="mot de passe"
de.password			="Passwort"
en.username			="username"
fr.username			="identifiant"
de.username			="Nutzername"
en.youremail			="your email"
fr.youremail			="votre email"
de.youremail			="deine E-Mail"
en.existing_urn				="It looks like you already have an account…"
de.existing_urn				="Offenbar haben Sie bereits ein Konto…"
fr.existing_urn				="Il semble que vous ayez déjà un compte…"
en.verify				="verify"
fr.verify				="vérifier"
de.verify				="zubehör"
en.send				="send"
fr.send				="envoyer"
de.send				="senden"
en.lastsignin			="Your last signin was"
fr.lastsignin			="Votre dernière connexion était"
en.signin_tip			= [[If you're using a shared computer, remember to <b>sign-out</b> when you're finished.]]
fr.signin_tip			= [[Si vous utilisez un ordinateur partagé, n'oubliez pas de vous déconnecter quand vous aurez fini.]]
de.signin_tip			= [[Wenn Sie einen gemeinsam genutzten Computer verwenden, denken Sie daran, sich abzumelden, wenn Sie fertig sind.]]
en.signin_password_hint	= [[Leave this blank if you've forgotten it.]]
fr.signin_password_hint	= [[Laissez ce champ vide si vous l'avez oublié.]]
de.signin_password_hint	= [[Lassen Sie dieses Feld leer, wenn Sie es vergessen haben.]]
en.signin_email_hint	= [[Use your <b>e-mail</b> address, <b>telephone</b> number, or <b>username</b>.]]
fr.signin_email_hint	= [[Utilisez votre adresse <b>e-mail</b>, numéro de <b>téléphone</b> ou <b>nom d'utilisateur</b>.]]
de.signin_email_hint	= [[Verwenden Sie Ihre <b>E-Mail</b> Adresse, <b>Telefonnummer</b> oder <b>Benutzername</b>.]]
en.signin_invalid		= [[<b>Oops</b>, your password was incorrect.]]
fr.signin_invalid		= [[<b>Oups</b>, votre mot de passe est incorrect.]]
de.signin_invalid		= [[<b>Ups</b>, Dein Passwort war falsch.]]
en.signin_disabled	= [[<b>Sorry</b>, too many incorrect signins have been attempted with that ID and it has been disabled.]]
fr.signin_disabled	= [[<b>Désolé</b>, trop de connexions incorrectes ont été tentées avec cette identification et il a été désactivé.]]
de.signin_disabled	= [[<b>Es tut uns leid</b>, mit dieser ID wurden zu viele falsche Anmeldungen versucht und sie wurde deaktiviert.]]
en.signin_unknown		= [[<b>Sorry</b>, we didn't recognise that identification.]]
fr.signin_unknown		= [[<b>Désolé</b>, nous n'avons pas reconnu cet identifiant.]]
de.signin_unknown		= [[<b>Es tut uns leid</b>, wir haben diese Identifikation nicht erkannt.]]
en.signin_unverified	= [[<b>Sorry</b>, your email address has not yet been verified, please <b>check your mailbox</b> and click the link in the message that has been sent to you.]]
fr.signin_unverified	= [[<b>Désolé</b>, votre adresse e-mail n'a pas encore été vérifiée, s'il vous plaît <b>vérifier votre boîte aux lettres</b> et cliquez sur le lien dans le message qui a été envoyé vers vous.]]
de.signin_unverified	= [[<b>Es tut uns leid</b>, ihre E-Mail-Adresse wurde noch nicht verifiziert, bitte <b>überprüfen Sie Ihr Postfach</b> und klicken Sie auf den Link in der Nachricht, die an Sie gesendet wurde.]]
en.signin_reminder	= [[Should we <a href="/Verify/??(address)">send you a sign-in link by email</a>?]]
fr.signin_reminder	= [[Faut-il vous <a href="/Vérifier/??(address)">envoyer un lien de connexion par e-mail</a>?]]
de.signin_reminder	= [[Sollen wir Ihnen <a href="/Verifizieren/??(address)">einen Anmeldelink per E-Mail senden?]]
en.signin_remind		= [[Submit your email address if you need a sign-in link sent to you.]]
fr.signin_remind		= [[Entrez votre adresse email si vous souhaitez être envoyé identifiants de connexion.]]
de.signin_remind		= [[Geben Sie Ihre E-Mail-Adresse an, wenn Sie einen Anmeldelink erhalten möchten.]]
en.signin_sent = "We've sent you a sign-in link, please <b>check your email in a few moments</b>. If you don't find it please check your spam."
de.signin_sent = "Haben wir Ihnen einen Anmeldelink gesendet. Bitte <b>überprüfen Sie Ihre E-Mails in wenigen Augenblicken</b>. Wenn Sie es nicht finden, überprüfen Sie bitte Ihren Spam."
fr.signin_sent = "Nous vous avons envoyé un lien de connexion, veuillez <b>vérifier votre messagerie dans quelques instants</b>. Si vous ne le trouvez pas, veuillez vérifier vos spams."
en.signin_checkemail	="We've already sent you an email, please check your spam. You can try again in a short while if you didn't receive it."
de.signin_checkemail	="Wir haben Ihnen bereits eine E-Mail gesendet, bitte überprüfen Sie Ihren Spam. Sie können es in Kürze erneut versuchen, wenn Sie es nicht erhalten haben."
fr.signin_checkemail	="Nous vous avons déjà envoyé un e-mail, merci de vérifier vos spams. Vous pouvez réessayer dans quelques minutes si vous ne l'avez pas reçu."

-- generic words
en.from				="from"
fr.from				="depuis"
de.from				="ab"
en['of']				="of"
fr['of']				="de"
de['of']				="von"
en['on']				="on"
fr['on']				="sur"
de['on']				="auf"
en['or']				="or"
fr['or']				="ou"
de['or']				="des"
en['to']				="to"
fr['to']				="à"
de['to']				="zu"
en['in']				="in"
fr['in']				="en"
de['in']				="in"
en['and']				="and"
fr['and']				="et"
de['and']				="und"
en['with']			="with"
fr['with']			="avec"
de['with']			="mit"
en.yes				="yes"
fr.yes				="oui"
de.yes				="ja"
en.no					="no"
fr.no					="non"
de.no					="kein"
en.default			="default"
fr.default			="inconnu"
de.default			="ursprünglich"
en.unspecified		="unspecified"
fr.unspecified		="indéterminé"
de.unspecified		="nicht spezifiziert"
en.unknown			="unknown"
fr.unknown			="inconnu"
de.unknown			="unbekannt"
en.none				="none"
fr.none				="aucune"
de.none				="keiner"
en.setup				="setup"
fr.setup				="coordonnées"
de.setup				="Konfiguratón"
en.actionregister		="Register me"
fr.actionregister		="S'inscrire"
de.actionregister		="Registriere mich"
en.actioncontinue		="Continue"
fr.actioncontinue		="Continuer"
de.actioncontinue		="Weiterführen"
en.save				="Save changes"
fr.save				="Enregistrer"
de.save				="Änderungen speichern"
en.choosepassword		="choose a password"
fr.choosepassword		="choisir un mot de passe"
de.choosepassword		="Wähle ein Passwort"
en.invalidpassword	="must be 6 characters or longer; we recommend using several random words, e.g.: sublime blue glass"
fr.invalidpassword	="doit contenir 6 caractères ou plus; nous recommandons d'utiliser plusieurs mots aléatoires, par exemple: sublime verre bleue"
de.invalidpassword	="muss mindestens 6 Zeichen lang sein; Wir empfehlen die Verwendung mehrerer zufälliger Wörter, z. B.: erhabenes blaues glas"
en.next				="next"
fr.next				="consécutif"
de.next				="nächste"
en.replace			="replace"
fr.replace			="remplacer"
de.replace			="ersetzen"
en.add				="add"
fr.add				="mettrez"
de.add				="hinzufügen"
en.remove				="supprimer"
fr.remove				="supprimer"
de.remove				="beseitigen"
en.delete				="delete"
fr.delete				="effacer"
de.delete				="löschen"
en.previous			="previous"
fr.previous			="précédent"
de.previous			="früher"
en.unavailable		="unavailable"
fr.unavailable		="non disponible"
de.unavailable		="nicht verfügbar"
en.begin				="begin"
fr.begin				="commencez"
de.begin				="beginnen"
en.congratulations	="congratulations!"
fr.congratulations	="féliciations !"
de.congratulations	="glückwünsche!"
en.create				="create"
fr.create				="créer"
de.create				="kreieren"
en.update				="update"
fr.update				="mettre à jour"
de.update				="aktualisieren"
en.welcome			="welcome"
fr.welcome			="bienvenue"
de.welcome			="willkommen"
en.alreadyused		="already claimed"
fr.alreadyused		="déjà utilisé"
de.alreadyused		="Bereits beansprucht"
en.post				="post"
fr.post				="afficher"
de.post				="verbuchen"
en['print']			="print"
fr['print']			="imprimer"
de['print']			="drucken"

-- validation
en.invalid			="invalid"
fr.invalid			="invalide"
de.invalid			="ungültig"
en.required			="required"
fr.required			="obligatoire"
de.required			="erforderlich"
en.optional			="optional"
fr.optional			="facultatif"
de.optional			="fakultativ"
-- errors
en.verifyfailure		=[[Perhaps you've already tried using that link? The link may only be used once, but you can get another by signing-in with only your email address.]]
fr.verifyfailure		=[[Peut-être avez-vous déjà essayé d'utiliser ce lien ? Le lien ne peut être utilisé qu'une seule fois, mais vous pouvez en obtenir un autre en vous connectant uniquement avec votre adresse e-mail.]]
de.verifyfailure		=[[Vielleicht hast du es schon einmal mit diesem Link versucht? Der Link darf nur einmal verwendet werden, aber Sie können einen weiteren erhalten, indem Sie sich nur mit Ihrer E-Mail-Adresse anmelden.]]
en.errorhead			="Oops, something's wrong"
de.errorhead			="Hoppla, etwas stimmt nicht"
fr.errorhead			="Oups, qqch a mal tourné"
de.errorhead			="Hoppla, ist etwas schief gelaufen ist"
en.notfound_title		="Unknown Page"
fr.notfound_title		="Page Inconnue"
de.notfound_title		="Unbekannte Seite"
en.notfound_head		="It's not here"
de.notfound_head		="Es ist nicht hier"
fr.notfound_head		="Ce n'est pas ici"
en.notfound_body		=[[It may have been removed, not yet created, or the address might be wrong.]]
fr.notfound_body		=[[Il peut avoir été enlevée, pas encore créé, ou l'adresse peut-être tort.]]
de.notfound_body		=[[Möglicherweise wurde es entfernt, noch nicht erstellt oder die Adresse ist falsch.]]
en.unknown_title		="Unknown domain"
fr.unknown_title		="Domaine inconnu"
de.unknown_title		="Unbekannte Domäne"
en.unknown_head		="Hmm, it's quiet around here…"
fr.unknown_head		="Hmm, il n'y a rien ici…"
de.unknown_head		="Hmm, hier ist es ruhig…"
en.unknown_body		=[[We're sorry, the site « ?(domain) » is not currently configured by its owner for use with ?(provider). But please do check back again soon!]]
fr.unknown_body		=[[Nous sommes désolés, le site « ?(domain) » n'est pas actuellement configuré par son propriétaire pour une utilisation avec ?(provider). Mais revenir bientôt!]]
de.unknown_body		=[[Es tut uns leid, die Website « ?(domain) » ist derzeit von ihrem Eigentümer nicht für die Verwendung mit ?(provider) konfiguriert. Aber bitte schauen Sie bald wieder vorbei!]]

en.verify_subject = [[Your signin for ?(service)]]
en.verify_message = [[You may signin using the following single-use link.
http://?(domain)/Verify/??(session)]]
fr.verify_subject = [[Votre connexion pour ?(service)]]
fr.verify_message = [[Vous pouvez vous connecter en utilisant le lien suivant (utilisable seule une fois).
http://?(domain)/Vérifier/??(session)]]
de.verify_subject = [[Ihre Anmeldung für ?(service)]]
de.verify_message = [[Über folgenden Link können Sie sich einloggen (nur einmal nutzbar).
http://?(domain)/Vérifier/??(session)]]
