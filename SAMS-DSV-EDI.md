# How to import dsv orders for SAMS

#### Note: DSV has an issue with imports to WinFashion when the address field of one of the POs. Whichever file it happens to we have to go in and update that to ensure it's under the character limit (character limit to be determined from WinFashion)

1. Go to quila server iSoft\inbox\walmart folder
2. To ensure that the files are DSV and not replenishment check if the file contains "Fedex" string and check of the file has.
    File size will be 10-15 kb for DSV
3. Qualifier is 08 Communication ID rollout and replenishment 925485US00 DSV Q ID 08 925485USSM
4. Rename these files to todays date and samsd. e,g `062426samsd (1).`
5. Go to EDI (850) Purhase Order
6. Go to SamsClub DSV
7. Click on Get Data button
8. Select the EDI files to be processed
    a. Note down any errors
9. Once imported note down how many POs were imported
10. got to sales order and click on the last button >|
11. Note down the last sales order number and input this in the edi spreadsheet in shee EDI 850
12. Go to sales order and then list all the orders that need to be picked. If this is a second batch use `picked < 1` filter.
13. Select all the orders
14. go to pick tickets.
15. Click multipick
16. Select all orders in the list.
17. Click select.
18. confirm you want to generate pick tickets.
19. go to utility -> other options -> Pick Carton Assignment
20. PickNo. from and to (either keep it from 2000 to 9999999) or specify the exact pick ticket range.
21. Change Max Qty Per Carton to 25. Leave Weight per piece to 1 (Means 1lb)
22. Click Cart.Assgnt (Pick and Pack)
23. go to pick tickets
24. multi print. hide price
25. Report pick  
26. Generate 997 & 855 and send it out in isoft/outbox/walmart folder