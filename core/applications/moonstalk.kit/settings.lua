
addresses = -- applications must declare all urns, as autourns is not an option
{
	{ starts="api/attributes", controller="kit/api/attributes", view=false, template=false, locks={"Operator","Manager","Administrator"}}, -- TODO: change this when the api app is done
}
