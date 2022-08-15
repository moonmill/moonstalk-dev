-- settings for generic views
database = {{name="sessions_user", index=true}, {name="sessions", file="node"}}
addresses = {
	-- There should be a signin address mapped for every supported language as it appears in localised signup and reminder emails
	{ matches={"signin","se-connecter"}, controller="signin", nocache=true, robots="none"},
	{ matches={"verify","verifier","zubehor"}, controller="verify", nocache=true, robots="none"},
	{ matches={"signout","quitter"}, action="Signout", nocache=true, robots="none"},
	{ matches="moonstalk.generic/localise", controller="localise", nocache=true, robots="none"},
	{ matches="moonstalk.generic/cookie", controller="cookie", nocache=true, robots="none"},
	--{ matches="my/account", controller="account", locks={"User"}, robots="none"}, -- a psuedo-key that all authorised users have -- FIXME: re-enable but needs a way to be replaced or not replace an address with a lower priority
}
authenticator = false -- don't enable on our own views

userSessionPieces = {locale="locale", language="language", timezone="timezone", id="id", name="name", nickname="nickname", last="last",} -- if you need to frequently access dfferent session pieces, override these values from your Starter; generic.userSessionPieces = {…}
userAccountPieces = {"locale","language,","timezone","emails","telephones","sessions","keychains","settings","urn"} -- only used on the account page -- TODO: will require a dedicated function or seperate view as sessions is now in another table
