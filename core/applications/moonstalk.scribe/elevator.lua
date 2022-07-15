if node.authenticator and not util.TablePath(node.authenticator) then
	moonstalk.Error{scribe,title="Invalid node.authenticator: "..node.authenticator}
end
