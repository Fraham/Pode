$path = Split-Path -Parent -Path (Split-Path -Parent -Path $MyInvocation.MyCommand.Path)
Import-Module "$($path)/src/Pode.psm1" -Force -ErrorAction Stop

# or just:
# Import-Module Pode

<#
This examples shows how to use session persistant authentication using Windows Active Directory.
The example used here is Form authentication, sent from the <form> in HTML.

Navigating to the 'http://localhost:8085' endpoint in your browser will auto-rediect you to the '/login'
page. Here, you can type the details for a domain user. Clicking 'Login' will take you back to the home
page with a greeting and a view counter. Clicking 'Logout' will purge the session and take you back to
the login page.
#>

# create a server, and start listening on port 8085
Server -Threads 2 {

    # listen on localhost:8085
    listen *:8085 http

    # set the view engine
    engine pode

    # setup session details
    middleware (session @{
        'Secret' = 'schwifty';
        'Duration' = 120;
        'Extend' = $true;
    })

    # setup form auth against windows AD (<form> in HTML)
    auth use login -t form -v 'windows-ad' -o @{
        'fqdn' = '<domain>';
        'groups' = @('<group>');
        'users' = @('<user>');
    }

    # home page:
    # redirects to login page if not authenticated
    route 'get' '/' (auth check login -o @{ 'failureUrl' = '/login' }) {
        param($e)

        $e.Session.Data.Views++

        view 'auth-home' -data @{
            'Username' = $e.Auth.User.Name;
            'Views' = $e.Session.Data.Views;
        }
    }

    # login page:
    # the login flag set below checks if there is already an authenticated session cookie. If there is, then
    # the user is redirected to the home page. If there is no session then the login page will load without
    # checking user authetication (to prevent a 401 status)
    route 'get' '/login' (auth check login -o @{ 'login' = $true; 'successUrl' = '/' }) {
        param($e)
        view -fm 'auth-login'
    }

    # login check:
    # this is the endpoint the <form>'s action will invoke. If the user validates then they are set against
    # the session as authenticated, and redirect to the home page. If they fail, then the login page reloads
    route 'post' '/login' (auth check login -o @{
        'failureUrl' = '/login';
        'successUrl' = '/';
        'failureFlash' = $true;
    }) {}

    # logout check:
    # when the logout button is click, this endpoint is invoked. The logout flag set below informs this call
    # to purge the currently authenticated session, and then redirect back to the login page
    route 'post' '/logout' (auth check login -o @{
        'logout' = $true;
        'failureUrl' = '/login';
    }) {}

}