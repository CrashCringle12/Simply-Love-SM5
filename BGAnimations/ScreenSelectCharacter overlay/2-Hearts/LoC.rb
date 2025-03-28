count = 0

Dir["**/*.lua"].each do |f|
   file =  File.open( f ).each do |line|
       count+=1
   end
end

puts count