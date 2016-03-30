def run_commands(commands)
  commands.each do |command|
    puts "\n-> #{command}"
    return false unless system(command)
  end
end

def bump_version_and_push_origin_master
  puts "updating loomio-production version and committing to github..."
  run_commands ['ruby script/bump_version patch',
                'git add lib/version',
                'git commit -m "bump version"',
                'git push origin master']
  Loomio::Version.reload
end

def setup_heroku
  puts "setup heroku"
  run_commands ["sh script/heroku_login.sh $DEPLOY_EMAIL $DEPLOY_PASSWORD",                       # login to heroku
                "echo \"Host heroku.com\n  StrictHostKeyChecking no\" > ~/.ssh/config"]           # don't prompt for confirmation of heroku.com host
end

def setup_git_remote(remote)
  puts "setup git remote #{remote}"
  run_commands ["git config user.email $DEPLOY_EMAIL && git config user.name $DEPLOY_NAME",       # setup git commit user
                "git remote add #{remote} https://git.heroku.com/#{remote}.git"]                  # add https heroku remote

end

def build_and_push_branch(remote, branch)
  puts "building assets and deploying to #{remote}/#{branch}..."
  build_branch = "deploy-#{remote}-#{branch}-#{Time.now.to_i}"
  run_commands ["git checkout #{branch}",                                                         # checkout branch
                "git checkout -b #{build_branch}",                                                # cut a new deploy branch off of that branch
                "rake 'plugins:acquire[loomio_org]' plugins:resolve_dependencies",                # install plugins specified in plugins/plugins.yml
                "rm -rf plugins/**/.git",                                                         # allow cloned plugins to be added to this repo
                "find plugins -name '*.*' | xargs git add -f",                                    # add plugins folder to commit
                "cd angular && npm install && gulp compile && cd ../",                            # build the app via gulp
                "cp -r public/client/development public/client/#{Loomio::Version.current}",       # version assets
                "git add public/client/#{Loomio::Version.current} public/client/fonts -f",        # add assets to commit
                "git commit -m 'Add compiled assets / plugin code'",                              # commit assets
                "git push #{remote} #{build_branch}:master -f",                                   # DEPLOY!
                "git checkout #{branch}",                                                         # switch back to original branch
                "git branch -D #{build_branch}"]                                                  # delete production branch
end

def heroku_migrate_and_restart(remote)
  puts "migrating and restarting heroku app #{remote}..."
  run_commands ["ruby /usr/local/heroku/bin/heroku run rake db:migrate -a #{remote}",
                "ruby /usr/local/heroku/bin/heroku restart -a #{remote}",
                "ruby /usr/local/heroku/bin/heroku run rake loomio:notify_clients_of_update -a #{remote}"]
end

desc "Deploy to some git-remote and branch"
task :deploy do
  load ENV['DEPLOY_PATH']
  Deploy.push!(*ARGV)
  exit 0
end
