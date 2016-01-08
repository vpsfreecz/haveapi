// Register built-in providers
c.Authentication.registerProvider('basic', basic);
c.Authentication.registerProvider('token', token);

var HaveAPI = {
	Client: Client
};
